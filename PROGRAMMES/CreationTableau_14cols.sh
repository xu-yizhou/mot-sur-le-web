#!bin/bash
#CreationTableau_14cols.sh
#REPERTOIRE d'exécution : $HOME/.../PROJET_MOT_SUR_LE_WEB
#fichier parametre :  ./PROGRAMMES/parametres
#fichier log : ./PROGRAMMES/log
#EXECUTION
#bash ./PROGRAMMES/CreationTableau_14cols.sh \
#< ./PROGRAMMES/parametres | tee ./PROGRAMMES/log
#VERSION : 18.01 alpha
#AUTEURS : Chunyang et Yizhou
#Note: "line wrap" par \ est appliqué 
# pour limiter la longeur maximale de chaque ligne 
################################################################################
#############################FONCTIONS MAJEURES#################################
#Ce script permet de collecter, filtrer et prétraiter des ressources langagières 
# à partier des URLs approvisonnées pour nos trois langues de travail ; 
# et de présenter les résultats obtenus dans une page HTML 
# sous forme d'un tableau de 14 colonnes pour chaque langue. 
#Attributs des colonnes
#N°: numéro
#LIEN : URL
#CODE : code http pour cette URL
#	1xx Information
#	2xx Succès
#	3xx Redirection
#	4xx Erreur du client web
#	5xx Erreur du serveur / du serveur d'application
#ETAT : état de cette URL
#P.A. : page HTML aspirée
#ENC. INIT : encodage initial (utf-8, gb2312, etc)
#DP INIT : texte dump en encodage initial
#DP NET UTF8 : texte dump utf8 formatté
#CTXT. UTF8 : contexte utf8, une ligne avant/après le motif
#CTXT. HTML : contexte généré à l'aide de minigrep
#FQ : fréquence du motif dans le texte dump utf8 formatté
#IND : index de lemmes du fichier contexte, par ordre de fréquence décroissante
#NGRAM : 2gram du fichier contexte, par ordre de fréquence décroissante
#TTR% : type/token ratio du fichier contexte
################################################################################
################################################################################

echo "Création d'une page html contenant trois tableaux ";
read rep;
read table;
read rep_page_aspiree;
read rep_dump_text;
read rep_contexte;
read motif;
read minigrep;
read motif_mini_grep;
read cn_stopwords;
read en_stopwords;
read fr_stopwords;

minigrep_out="./resultat-extraction.html";
#Il vaut mieux écrire les 3 paramètres infra dans ce script que 
#dans le fichier paramètre pour éviter
#des problèmes de permissions éventuels.
dictionnaire_scws=~/scws/etc/dict_utf8_cmplt.xdb;
en_param=$HOME/treetagger/lib/english-utf8.par;
fr_param=$HOME/treetagger/lib/french-utf8.par;
COL_NUM=14;
################################################################################
#################################BLOC FONCTIONS#################################
################################################################################

################################################################################
#Fonction qui permet d’écrire des en-têtes (balise <th>) d’un tableau.
#Paramètres : 
#$1 : la largeur de la colonne en pourcentage (width) ;
#$2 : le titre de la colonne
#Appel : 
#Pour créer n en-têtes, il faut appeler n fois la fonction et 
# passer 2 variables pour chaque appel.
#Sortie : 
#La sortie par défaut est sur le stdOUT, il faut la rédiriger 
# vers le fichier HTML final.
write_thead () {
	echo -e "\t\t\t\t<th width = \"$1\" align = \"center\">$2</th>";
}
################################################################################
#Fonction qui écrit le contenu de chaque case (cell) d’un tableau ; 
# elle constitue la fonction write_line (). 
#Paramètres :
#$1 : le contenu de case entouré dans le balise <td>.
#Appel :
#Une variable à passer pour chaque appel. 
#Sortie :
#La sortie par défaut est sur le stdOUT, 
# il faut la rédiriger vers le fichier HTML final.
write_cell () {
	echo -e "\t\t\t\t<td align = \"center\">$1</td>";
}
################################################################################
#Fonction qui remplit le tableau ligne par ligne 
# en appelant la fonction write_cell(). 
#Paramètre global :
#$COL_NUM, constant.
#Paramètres :
#$i : local, compteur ;
#$j : local, assignée par référence indirecte, désigne la jième colonne.
#Appel : 
#Dans notre script, il y a 14 variables à passer pour cette fonction : 
# chacune d’entre elles correspond à une colonne. Notre tableau en comporte 14.
#Sortie :
#$La sortie par défaut est sur le stdOUT, il faut la rédiriger 
# vers le fichier HTML final.
write_line () {
	# 
	echo -e "\t\t\t<tr>";
	local i=1;
	local j;
	while [ $i -le $COL_NUM ] ; do
	    eval j=\${$i}; 
	    write_cell "$j"; 
	    ((i++));
	done	
	echo -e "\t\t\t</tr>";
}
################################################################################
#Fonction qui récupère l’encodage à l’aide de curl, 
# commande qui envoie au serveur une requête de l’en-tête par l’option -I.
#Paramètre :
#$1 : une URL.
#Appel : 
#La variable désignant une URL à passer pour l’appel (dans le script : $line ).
#Sortie :
#La valeur est passée par substitution de commande.
get_remote_encoding () {
	 
	curl -sIL $1|grep -i -Po '(?<=charset=).+(?=\b)' | \
	awk '{print tolower($0)}';
}
################################################################################
#Fonction qui récupère l’encodage dans le balise <meta> d’une page HTML ;
#Paramètre :
#$1 : une page HTML aspirée.
#Appel : 
#La variable désignant une page HTML à passer pour l’appel 
# (dans le script : $page).
#Sortie :
#La valeur est passée par substitution de commande.
get_page_encoding () {
	
	egrep -i 'meta.+charset' $1 |awk '{print tolower($0)}' | \
	egrep -o "charset[=\s\"a-Z0-9\-]*" |cut -d"=" -f2 | \
	sed  's/\s//g'|sed 's/\"//g';
}
################################################################################
#Fonction qui vérifie si l’encodage est reconnu par la commande iconv.
#Paramètre :
#$1 : un encodage.
#Appel :
#La variable désignant l’encodage à passer pour l’appel 
# (dans le script : $encodage).
#Sortie :
#La valeur est passée par substitution de commande. 
#Si celle-ci est vide, le fichier correspondant 
# ne peut pas être transcodé par iconv.
check_encoding () {	
	iconv -l | egrep -io $1 | sort -u;
}
################################################################################
#Fonction qui 
# 1) nettoie un fichier composé de l’alphabet latin 
# en supprimant des « bruits », tels que des titres des rubriques, 
# des listes des articles récents, des noms des images, etc, 
# qui sont en général marqués par des caractères spéciaux ; 
# 2) et le formatte de manière « syntaxique », 
# c’est-à-dire que l’on touche le « line wrap » et met chaque phrase par ligne.
#Paramètre :
#$1 : un ficher texte, dans notre script, 
# un fichier dump utf-8 de l’anglais ou du français.
#Appel (par exemple) : 
#format_latin_text < MonFichierAFormatter > MonFichierBienFormatté;
#Sortie : La sortie par défaut est sur le stdOUT, 
# il faut la rédiriger vers le fichier formatté.
format_latin_text () {
	sed -r "/[\*\+▪] |\*$|\#|\[.*\]|[=&]|IFRAME|__|©|(c|C)opyright|\
	\( \)|(BUTTON)|http|www|  \b[0-9]+\.|\.jpe?g|png|JPE?G|PNG|\
	<.*[^>]>|[<>]|[a-Z0-9+=%]{30}|^$/d" $1 | tr '\n' ' '| \
	tr -s ' ' | sed 's/[.?!]/&\n/g';	
} 
################################################################################
#Fonction similaire, mais ne traite que des textes chinois (sans délimiteur). 
# Elle permet de 1) nettoyer et 2) formatter un texte, 3) 
# et de le segmenter avec le tokenizer scws.
#Paramètre global :
#$dictionnaire_scws : le chemin du dictionnaire du tokenizer scws ; 
# le dictionnaire est paramétrable.
#Paramètre :
#$1 : un fichier texte chinois encodé en utf-8.
#Appel :
#pareil à la fonction format_latin_text ()
#Sortie : 
#La sortie par défaut est sur le stdOUT, 
# il faut la rédiriger vers le fichier formatté.
format_chinese_text () {
	sed -r "/[\*\+] |\[.*\]|[=&¿]|IFRAME|__|©|(c|C)opyright|\( \)|\
	BUTTON|\||http|www|  \b[0-9]+\.|\.jpe?g|png|JPE?G|PNG|<.*[^>]>|\
	[<>]|^$/d" $1 | tr -d '\n' | \
	tr -d ' ' |sed "s/[。？！]/&\n/g" | \
	scws -c utf8 -d $dictionnaire_scws;
}
################################################################################
#Fonction qui décharge le texte d’une page HTML à partir de l’URL.
#Il faut désignier le jeu de caractères pour la commande lynx 
# en utilisant les options -assume_charset et -display_charset 
# car quelques fois celle-ci ne peut pas réussir à décharger des textes 
# sans connaissances d’encodages préalables.
#Paramètres : 
#$1 : l’encodage correspondant au paramètre $2 ;
#$2 : une URL.
#Appel : 
#Les variable désignants l’encodage (dans le script : $encodage) et 
# l’URL correspondant (dans le script : $line) à passer pour l’appel.
#Sortie :
#La sortie par défaut est sur le stdOUT, 
# il faut la rédiriger vers un fichier dump texte.
get_text () {
	lynx -dump -nolist -assume_charset=%{charset} -display_charset=$1 $2;
}
################################################################################
#Fonction qui produit le contexte d’un motif. 
#Les lignes contenant -- qui délimitent des contextes, 
# ainsi que des lignes vides sont enlevés.
#Paramètres :
#$1 : nombre de ligne(s) à extraire avant/après la ligne contenant le motif ;
#$2 : un motif ;
#$3 : un fichier texte.
#Appel (par exemple) :
#get_contexte 1 “MonMotif” “NomDeMonFichierAExtraire” \
#> “NomDeMonFichierContexte”
#Sortie : La sortie par défaut est sur le stdOUT, 
# il faut la rédiriger vers un fichier contexte.
get_context () {
	egrep -i -C $1 "$2" $3 | sed '/^--|^$/d';
}
################################################################################
#Fonction qui produit le contexte d’un motif à l’aide de minigrep 
# et le déplace dans un répertoire souhaité.
#Paramètre global :
#$minigrep : le chemin du programme minigrep.
#Paramètres : 
#$1 : un fichier dump (formatté) ;
#$2 : nom du fichier contenant le motif ;
#$3 : $minigrep_out, nom du fichier HTML généré par minigrep ;
#$4 : la destination du déplacement du fichier $3.
#Appel (par exemple) : 
#get_context_html $dump-utf8-formatted $motif_mini_grep \
#$minigrep_out $contexte_html;
#Sortie : le déplacement du fichier sortant est réalisé par la commande mv.
get_context_html () {
	perl $minigrep "UTF-8" $1 $2;
	mv $3 $4
}
################################################################################
#Fonction qui calcule le nombre d’occurrences d’un motif dans un fichier texte.
#Paramètres :
#$1 : un motif ;
#$2 : un fichier texte formatté (avec la fonction format_latin_text () 
# ou format_chinese_text ()). 
# Sinon, on risque de perdre certaine occurrence à cause de « line wrap ».
#Appel (par exemple) : 
#fq=`get_frequency “MonMotif” MonFichierTexteBienFormatté`;
#Sortie :
#La valeur est passée par substitution de commande.
get_frequency () {
	egrep -io "$1" $2 | wc -l;
}
################################################################################
#Fonction qui sépare des tokens par ligne pour préparer des index, 
# des ngram, etc ; Les signes de ponctuations indésirables sont enlevées ; 
# Quelque fois, \w produit des bruits, on énumère donc bêtement 
# des signes de ponctuations ;
# On garde des tokens de genre mots polylexicaux composés 
# par des traits d’union, tels que « chassé-croisé » ;
#Paramètre :
#$1 : fichier (con)texte formatté, selon des objectifs.
#Appel (par exemple) : 
#token_to_line MonFichierAChanger > MonFichierQuiAUnTokenParLigne;
#Sortie :
#La sortie par défaut est sur le stdOUT, 
# il faut la rédiriger vers le fichier de liste de tokens.
token_to_line () {
	sed -r "s/[,.«»()\?\!…:;\"\‘\’*#。？！，、…+=%&：；【】\
	·　—“”–《》（）<>_■€\$\￥£•@②]|--| - / /g" $1 | \
	tr '\n' ' ' | tr ' ' '\n'| tr -s '\n'| sed "/^$/d" ;
}
################################################################################
#Fonction qui lemmatize une liste de tokens avec tree-tagger. 
# Les nombres, marqués par NUM en français et CD en anglais, sont enlevés. 
#Paramètres :
#$1 : fichier de liste de tokens à traiter ;
#$2 : fichier paramètre du tree-tagger.
#Appel (par exemple) : 
#lemmatize MonFichierTokens FichierParamTree_tagger > MonFichierLemme;
#Sortie :
#La sortie par défaut est sur le stdOUT, 
# il faut la rédiriger vers le fichier de liste de lemmes.
lemmatize () {
	sed -r "s/[’\']/\n/g" $1| tree-tagger $2 -lemma -no-unknown | \
	sed -r "/NUM.+|CD.+/d" |sed "/^$/d" | cut -f2 ;
}
################################################################################
#Fonction qui produit un index de tokens (formes) ou de types (lemmes) 
# par ordre de fréquence décroissante.
#Paramètre :
#$1 : fichier de liste de tokens ( ou de types).
#Appel (par exemple) : 
#get_index MonFichierDeListeDeTokens > MonFichierIndex;
#Sortie : 
#La sortie par défaut est sur le stdOUT, 
# il faut la rédiriger vers un fichier index.
get_index () {
	sort -bdfi $1 |uniq -ci | sort -gr;
}
################################################################################
#Fonction qui crée une liste de 2gram à partir d’un fichier de liste de tokens.
#Le fichier (temp1), après avoir été enlevé la première ligne 
# (avec la commande tail), est passé à une nouvelle variable locale (temp2) ; 
# Ces deux fichiers collés (avec la commande paste) 
# consitituent une liste contenant pour chaque ligne un 2gram ;
# Le sort de cette liste est réalisé 
# par la fonction « fait-maison » get_index () ;
# Le fichier temporaire est supprimé à la fin de l’exécution.
#Paramètres :
#temp1 ($1) : local, fichier de liste de tokens ;
#temp2 : local, le même fichier sans la première ligne.
#Appel :
#La variable désignant le fichier de liste de tokens à passer pour l’appel
# (dans le script : $contexte-tok).
#Sortie : La sortie par défaut est sur le stdOUT, 
# il faut la rédiriger vers un fichier 2gram.
get_2gram () {
	temp1=$1;
	local temp2=tp2;
	tail -n +2 $temp1 > $temp2;
	paste $temp1 $temp2 | get_index;
	rm $temp2;
}
################################################################################
#Fonction qui calcule le type/token ratio (ttr) d’un certain fichier.
# Le résultat est representé en pourcentage.
#Paramètres :
#$type_nb : local, compté par le nombre de lignes 
# dans le fichier de liste de lemmes ;
#$token_nb : local, compté par le nombre de ligne 
# dans le fichier de liste de tokens ;
#$1 : fichier de l’index de lemmes ;
#$2 : fichier de liste de tokens (ie, le « contexte » d’où viennent les lemmes).
#Appel (par exemple) : 
#ttr=`get_ttr $index $contexte-tok`;
#Sortie :
#La valeur est passée par substitution de commande.
get_ttr () {
	local type_nb=`cat $1 | wc -l`;
	local token_nb=`cat $2 | wc -l`;
	echo $(( 100 * type_nb / token_nb ));
}
################################################################################
#Fonction qui enlève des mots vides (stopwords) à partir d’un antidictionnaire ;
# -F interprète MOTIF comme une liste de chaînes fixées et séparées par ligne
# -f lit MOTIF depuis un fichier ;
# -v sélectionne des « non-matching » lignes ;
# -x sélectionne ceux qui « match » exactement la ligne ;
#Paramètres :
#$1 : fichier d’antidictionnaire (un token par ligne) ;
#$2 : fichier de liste de tokens à nettoyer (un token par ligne) ;
#Appel (par exemple) : 
#remove_stopwords MonAntiDictionnaire MonFichierDeListeDeTokens
#Sortie : 
#La sortie par défaut est sur le stdOUT, 
# il faut la rédiriger (dans notre scrpit, 
# celle-ci est dans une chaîne de traitements).
remove_stopwords () {
    grep -Fvxf $1 $2;
}
################################################################################
#Fonction qui concatène des fichiers dans un seul fichier global ;
# Chaque fichier est entouré par une paire de balises : <t>...</t> ;
# Dans le balise ouvrant, on ajoute un attribut qui marque son « identité » ;
# Comme les signes <, > sont enlevés dans les phases (fonctions) de 
# formalisation/normalisation, on ne les traite pas ici.
#Paramètres :
#$1 : attribut du balise, par exemple le numero de ce fichier ($line_iterator) ;
#$2 : nom du fichier individu à concaténer.
#Appel (par exemple) : 
#concatenate $line_iterator $contexte >> $contexte_whole;
#Sortie :
#Sortie : La sortie par défaut est sur le stdOUT, 
# il faut la rédiriger vers le fichier global sans effaçant le contenu existant.
concatenate () {
    echo "<t=\"$1\">"
    cat $2;
    echo -e "\n</t>";
}
################################################################################
#################################BLOC FONCTIONS#################################
################################################################################
echo "INPUT : nom du répertoire contenant des fichiers d'URLs : $rep"; 
echo "OUTPUT : nom du fichier html contenant des tableaux : $table";
echo "OUTPUT : nom du répertoire stockant les pages aspirées : \
$rep_page_aspiree";
echo "OUTPUT : nom du répertoire stockant les texts dump : $rep_dump_text";
echo -e "Motifs de recherche :\n\t$motif\n";
echo "OUTPUT : nom du répertoire stockant les fichiers contextes : \
$rep_contexte";
echo "OUTPUT : nom du répertoire stockant les fichiers index : \
$rep_contexte/INDEX";
echo "OUTPUT : nom du répertoire stockant les fichiers ngram : \
$rep_contexte/NGRAM";

################################################################################
######################DEBUT DU BLOC D'ECRITURE DU FICHER HTML###################
################################################################################
echo -e "<!DOCTYPE html>\n<html>\n\t<head>\n\t\t<title>TABLEAUX URLs</title>\
\n\t\t<meta charset=\"utf-8\">\n\t</head>\n" > $table;
echo -e "\t<body>\n\t\t<h2 align=\"center\">\
TABLEAUX des URLs</h2>" >> $table;

################################################################################
#############BLOC DU TRAITEMENT D'URLS ET D'ECRITURE DU FICHER HTML#############
################################################################################
for file in `ls $rep | sort -r`
{
    echo -e "\t\t<table id = \"$file\" border = \"1\" \
    width = \"100%\" align = \"center\">" >> $table;
    # titre du tableau
    if [[ "$file" == "CN" ]] ;then
	echo -e "\t\t\t<tr height = \"30px\"> \
    <th colspan = \"$COL_NUM\">Chinois de Chine continentale</th></tr>" \
    >> $table;
    elif [[ "$file" == "EN" ]] ;then
	echo -e "\t\t\t<tr height = \"30px\"> \
    <th colspan = \"$COL_NUM\">Anglais de Royaume-Uni</th></tr>" >> $table;
    else
	echo -e "\t\t\t<tr height = \"30px\"> \
    <th colspan = \"$COL_NUM\">Français de France</th></tr>" >> $table;
    fi;
    
	# Ecrire des en-têtes d'un tableau
    echo -e "\t\t\t<tr>" >> $table;
    # colonne1 : numéro
    write_thead 3% "<abbr title=\"Numéro de lien\">N°</abbr>" >> $table;
    # colonne2 : lien
    write_thead 5% 'LIEN' >> $table;
    # colonne3 : code d'état
    write_thead 5% "<abbr title=\"Code retour HTTP\">CODE</abbr>" >> $table;
    # colonne4 : état de lien
    write_thead 8% "<abbr title=\"Etat de lien\">ETAT</abbr>" >> $table;
    # colonne5 : page aspirée
    write_thead 5% "<abbr title=\"Page aspirée\">P.A.</abbr>" >> $table;
    # colonne6 : encodage initial
    write_thead 7% "<abbr title=\"Encodage initial\">ENC. INIT</abbr>" >> $table;
    # colonne7 : dump initial
    write_thead 7% "<abbr title=\"Dump texte initial\">DP INIT</abbr>" >> $table;
    # colonne8 : dump utf-8
    write_thead 8% "<abbr title=\"Dump texte nettoyé utf8\">DP NET UTF8</abbr>"\
    >> $table;
    # colonne9 : contexte extrait à l'aide de commande egrep
    write_thead 8% "<abbr title=\"Contexte utf8\">CTXT. UTF8</abbr>" >> $table;
    # colonne10 : contexte au format html extrait à l'aide de minigrep 
    write_thead 9% "<abbr title=\"Contexte html\">CTXT. HTML</abbr>" >> $table;
    # colonne11 : fréquence de motif
    write_thead 4% "<abbr title=\"Fréquence du motif\">FQ</abbr>" >> $table;
    # colonne12 : index (lemmes avec leur fréquence) 
    write_thead 5% "<abbr title=\"Index des lemmes(sauf le chinois)\">\
    IND.</abbr>" >> $table;
    # colonne13 : ngram ==> 2gram
    write_thead 6% 'NGRAM' >> $table;
    # colonne14 : ttr(type/token ratio)
    write_thead 5% "<abbr title=\"Type/Token Ratio\">TTR%</abbr>" >> $table;
    echo -e "\t\t\t</tr>" >> $table;
    
    #Le fichier des textes dumps(formattés) en entier pour une langue
    dump_whole="$rep_dump_text/$file-dump-whole";
    #Le fichier des contextes en entier pour une langue
    contexte_whole="$rep_contexte/$file-contexte-whole";
    #Le fichier de l'index en entier pour une langue
    index_whole="$rep_contexte/INDEX/$file-index-whole";
    #Le fichier où stockant le ttr des échantillons pour une langue
    ttr_stat="$rep_contexte/$file-ttr-stat";
    #Le fichier où stockant la fréquence du motif 
    #	dans chaque échantillon pour une langue
    fq_stat="$rep_contexte/$file-fq-stat";
    
    line_iterator=0;
    for line in `cat $rep/$file`
    {
        
        ((line_iterator++));

        page="$rep_page_aspiree/$file-aspiree-$line_iterator.html";
        dump="$rep_dump_text/$file-dump-$line_iterator";
        contexte="$rep_contexte/$file-ctxt-$line_iterator";
        contexte_html="$rep_contexte/$file-ctxt-html-$line_iterator";
        index="$rep_contexte/INDEX/$file-index-$line_iterator";
        bigram="$rep_contexte/NGRAM/$file-2gram-$line_iterator";
        
        # Récupérer l'état de lien d'une URL par la commande curl 
	#	qui envoie une requête au serveur
        lien_statut=`curl -sIL $line|egrep -i 'HTTP\/[0-9]\.[0-9]'| \
        awk '{print $0}' | sed 's/\n/\t/g'|sed 's/\r/\t/g'`;
        
        # Récupérer le code de retour d'une URL 
        #  en envoyant une requête au serveur
        # Aspirer en même temps la page html correspondant.
        code_retour=`curl -sL -o $page -w "%{http_code}" $line | \
        sed 's/\n//g'|sed 's/\r//g'`;
        
        echo -e "\n############################################################"
        echo "###################$file-URL-$line_iterator EN COURS#############"
        echo "Etat de lien : $lien_statut"; 
        echo "Code_retour : $code_retour"; 

        # Structure de contrôle primaire : le code de retour (200 || d'autres)
        if [[ $code_retour == 200 ]] ; then
            # Récupérer l'encodage : deux manières
            encodage=`get_remote_encoding $line`;
            if [[ $encodage == "" ]] ; then
		encodage=`get_page_encoding $page`;
            fi;
            echo "Encodage : $encodage";
            
            # Structure de contrôle secondaire : l'encodage("utf-8" || d'autres)
            if [[ $encodage == "utf-8" ]] ; then
		get_text $encodage $line > $dump-utf8;
		
		# Structure de contrôle tierce : 
		#	$file : la langue (CN || d'autres)
		if [[ "$file" == "CN" ]] ;then
		    format_chinese_text < $dump-utf8 > $dump-utf8-formatted;
		    get_context 1 "$motif" $dump-utf8-formatted > $contexte;
		    get_context_html $dump-utf8-formatted \
		    $motif_mini_grep $minigrep_out $contexte_html;
		    
		    fq=`get_frequency "$motif" $dump-utf8-formatted`;
		    echo -e "$line_iterator\t$fq" >> $fq_stat;
		    echo "fq du motif : $fq";
		    
		    token_to_line $contexte > $contexte-tok;
		    get_index $contexte-tok > $index;
		    cat $contexte-tok >> $contexte_whole-lst;
		    get_2gram $contexte-tok > $bigram;
		    ttr=`get_ttr $index $contexte-tok`;
		    echo -e "$line_iterator\t$ttr" >> $ttr_stat;
		    echo "type/token ratio : $ttr";
		else # $file (EN et FR)
		    format_latin_text < $dump-utf8 > $dump-utf8-formatted;
		    get_context 1 "$motif" $dump-utf8-formatted > $contexte;
		    get_context_html $dump-utf8-formatted \
		    $motif_mini_grep $minigrep_out $contexte_html;
		    
		    fq=`get_frequency "$motif" $dump-utf8-formatted`;
		    echo -e "$line_iterator\t$fq" >> $fq_stat;
		    echo "fq du motif : $fq";
		    
		    token_to_line $contexte > $contexte-tok;
		    # lemmatizer le texte selon sa langue(file name)
		    if [[ "$file" == "EN" ]] ;then
			lemmatize $contexte-tok $en_param > $contexte-lemme;
		    else
			lemmatize $contexte-tok $fr_param > $contexte-lemme;
		    fi # $file  EN || FR
		    
		    get_index $contexte-lemme > $index;
		    cat $contexte-lemme >> $contexte_whole-lst;
		    get_2gram $contexte-tok > $bigram;
		    ttr=`get_ttr $index $contexte-tok`;
		    echo -e "$line_iterator\t$ttr" >> $ttr_stat;
		    rm $contexte-lemme $contexte-tok ;
		    echo "type/token ratio : $ttr";
		    
		fi # $file CN || d'autres
		
		# Concatener chaque fichier
		# Pour éviter "garbage in garbage out", 
		# on opte pour des fichiers nettoyés et formattés.
		concatenate $line_iterator $dump-utf8-formatted >> $dump_whole;
		concatenate $line_iterator $contexte >> $contexte_whole;
		
		# Ecrire une ligne d'un tableau
		write_line "$line_iterator" \
		"<a target=\"view_window\" href='$line'>\
		lien-$line_iterator</a>" \
		"$code_retour" \
		"$lien_statut" \
		"<a target=\"view_window\" href=\".$page\">\
		ap-$line_iterator</a>" \
		"$encodage" \
		"-" \
		"<a target=\"view_window\" href=\".$dump-utf8-formatted\">\
		dp-net-$line_iterator</a>" \
		"<a target=\"view_window\" href=\".$contexte\">\
		ctxt-$line_iterator</a>" \
		"<a target=\"view_window\" href=\".$contexte_html\">\
		ctxt-html-$line_iterator</a>" \
		"$fq" \
		"<a target=\"view_window\" href=\".$index\">\
		ind-$line_iterator</a>" \
		"<a target=\"view_window\" href=\".$bigram\">\
		2gram-$line_iterator</a>" \
		"$ttr" >> $table;
		
	    else # condition $encodage non utf-8
		verification_iconv=`check_encoding $encodage`;
		
		# condition $verification_iconv : vide||non (convertible ou pas)
		if [[ $verification_iconv != "" ]] ; then
		    get_text $encodage $line > $dump-$encodage;
		    iconv -c -f $encodage -t utf-8 $dump-$encodage > $dump-utf8;
		    
		    if [[ "$file" == "CN" ]] ;then
			format_chinese_text < $dump-utf8 > $dump-utf8-formatted;
			get_context 1 "$motif" $dump-utf8-formatted > $contexte;
			get_context_html $dump-utf8-formatted \
			$motif_mini_grep $minigrep_out $contexte_html;
			fq=`get_frequency "$motif" $dump-utf8-formatted`;
			echo -e "$line_iterator\t$fq" >> $fq_stat;
			echo "fq du motif : $fq";
			token_to_line $contexte > $contexte-tok;
			get_index $contexte-tok > $index;
			cat $contexte-tok >> $contexte_whole-lst;
			get_2gram $contexte-tok > $bigram;
			ttr=`get_ttr $index $contexte-tok`;
			echo -e "$line_iterator\t$ttr" >> $ttr_stat;
			echo "type/token ratio : $ttr";
		    else  # $file EN et FR
			format_latin_text < $dump-utf8 > $dump-utf8-formatted;
			get_context 1 "$motif" $dump-utf8-formatted > $contexte;
			get_context_html $dump-utf8-formatted \
			$motif_mini_grep $minigrep_out $contexte_html;
			fq=`get_frequency "$motif" $dump-utf8-formatted`;
			echo -e "$line_iterator\t$fq" >> $fq_stat;
			echo "fq du motif : $fq";
			token_to_line $contexte > $contexte-tok;
			
			if [[ "$file" == "EN" ]] ;then
			    lemmatize $contexte-tok $en_param > $contexte-lemme;
			else
			    lemmatize $contexte-tok $fr_param > $contexte-lemme;
			fi  # $file  EN FR
			get_index $contexte-lemme > $index;
			cat $contexte-lemme >> $contexte_whole-lst;
			get_2gram $contexte-tok > $bigram;
			ttr=`get_ttr $index $contexte-tok`;
			echo -e "$line_iterator\t$ttr" >> $ttr_stat;
			rm $contexte-lemme $contexte-tok ;
			echo "type/token ratio : $ttr";
			
		    fi  # $file CN, d'autres
		    
		    concatenate $line_iterator $dump-utf8-formatted \
		    >> $dump_whole;
		    concatenate $line_iterator $contexte >> $contexte_whole;
		    
		    write_line "$line_iterator" \
		    "<a target=\"view_window\" href='$line'>\
		    lien-$line_iterator</a>" \
		    "$code_retour" \
		    "$lien_statut" \
		    "<a target=\"view_window\" href=\".$page\">\
		    ap-$line_iterator</a>" \
		    "$encodage" \
		    "<a target=\"view_window\" href=\".$dump-$encodage\">\
		    dp-init-$line_iterator</a>" \
		    "<a target=\"view_window\" href=\".$dump-utf8-formatted\">\
		    dp-net-$line_iterator</a>" \
		    "<a target=\"view_window\" href=\".$contexte\">\
		    ctxt-$line_iterator</a>" \
		    "<a target=\"view_window\" href=\".$contexte_html\">\
		    ctxt-html-$line_iterator</a>" \
		    "$fq" \
		    "<a target=\"view_window\" href=\".$index\">\
		    ind-$line_iterator</a>" \
		    "<a target=\"view_window\" href=\".$bigram\">\
		    2gram-$line_iterator</a>" \
		    "$ttr" >> $table;		
		else  # condition $encodage
		    echo "Echec : $encodage inconnu...";
		    write_line "$line_iterator" \
		    "<a target=\"view_window\" href='$line'>\
		    lien-$line_iterator</a>" \
		    "$code_retour" \
		    "$lien_statut" \
		    "-" \
		    "$encodage" \
		    "-" \
		    "-" \
		    "-" \
		    "-" \
		    "-" \
		    "-" \
		    "-" >> $table;
		fi;  # condition $verification_iconv
            fi;  # condition $encodage
        else  # $code_retour != 200    
	
             echo "Echec : $lien_statut"; 
             write_line "$line_iterator" \
             "<a target=\"view_window\" href='$line'>lien-$line_iterator</a>" \
             "$code_retour" \
             "$lien_statut" \
             "-" \
             "-" \
             "-" \
             "-" \
             "-" \
             "-" \
             "-" \
             "-" \
             "-" >> $table; 
        fi  # condition $code_retour
        }
    get_index $contexte_whole-lst > $index_whole;
    if [[ "$file" == "CN" ]] ;then
	remove_stopwords $cn_stopwords $contexte_whole-lst \
	| get_index > $index_whole-filtre ;
    elif [[ "$file" == "EN" ]] ;then
	remove_stopwords $en_stopwords $contexte_whole-lst \
	| get_index > $index_whole-filtre ;
    else
	remove_stopwords $fr_stopwords $contexte_whole-lst \
	| get_index > $index_whole-filtre ;
    fi;
    # Ecrire la ligne récapitulative
    echo -e "\t\t\t<tr><td colspan = \"7\" style=\"background-color:#111111\">\
    </td>" >> $table;
    write_cell "<a target=\"view_window\" href=\".$dump_whole\">\
    dp-net</a>" >> $table;
    write_cell "<a target=\"view_window\" href=\".$contexte_whole\">\
    ctxt</a>" >> $table;
    echo -e "\t\t\t\t<td style=\"background-color:#111111\"></td>" >> $table;
    write_cell "<a target=\"view_window\" href=\".$fq_stat\">fq</a>" >> $table;
    write_cell "<a target=\"view_window\" href=\".$index_whole\">ind-b</a><br/>\
    <a target=\"view_window\" href=\".$index_whole-filtre\">ind-f</a>" >> $table;
    echo -e "\t\t\t\t<td style=\"background-color:#111111\"></td>" >> $table;
    write_cell "<a target=\"view_window\" href=\".$ttr_stat\">ttr</a>" >> $table;
    echo -e "\t\t\t</tr>" >> $table;
    
    echo -e "\t\t</table>\n" >> $table;
    
    echo -e "\t\t<br/>\n\t\t<hr width = \"100%\" \
    cb 9 size = \"5\">\n\t\t<br/>" >> $table; # horizontal rule
}
echo -e "\t</body>\n</html>" >> $table;
################################################################################
#######################FIN DU BLOC D'ECRITURE DU FICHER HTML####################
################################################################################
echo "Fin de création des tableaux.";