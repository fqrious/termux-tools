#!/bin/bash - 
#===============================================================================
#
#          FILE: ytget.sh
# 
#         USAGE: ./ytget.sh 
# 
#   DESCRIPTION: 
# 
#       OPTIONS: ---
#  REQUIREMENTS: yt-dlp ffmpeg awk mktemp numfmt
#          BUGS: ---
#         NOTES: ---
#        AUTHOR: Chaos Monarch (fqrious), fqrious@gmail.com
#  ORGANIZATION: 
#       CREATED: 09/02/21 10:42:08
#      REVISION:  ---
#===============================================================================

function log(){
	echo $@
}

function check_dependencies()(
	r=0
	for i in "${@}"; do
		command -v $i > /dev/null
		if [ $? -ne 0 ]; then
			log "dependency check failed for $i, please install"
			r=1
		fi
	done
	return $r
)

check_dependencies yt-dlp ffmpeg awk mktemp numfmt || exit

HEIGHT=720
FROM=0
DURATION=30
EXT=mp4

PROGNAME=${BASH_SOURCE[0]##*/}

function get_seconds(){
	echo $1 | awk -F: '{ if (NF == 1) {print $NF} else if (NF == 2) {print $1 * 60 + $2} else if (NF==3) {print $1 * 3600 + $2 * 60 + $3} }' ;
}

calc(){
	awk "BEGIN { print $*}";
}


function get_hhmmss(){
	time=$(calc "int( $1 )")
	hh=$(( $time / 3600 ))
	time=$(calc $time % 3600 )

	mm=$(($time / 60))

	ss=$( calc $1 % 60 )

	[[ $hh -eq 0  ]] || printf "%02d:%02d:" $hh $mm
	[[ $hh -eq 0  ]] && [[ $mm -ne 0  ]] && printf "%02d:" $mm
	printf "%05.2f\n" $ss
}


function get_temp(){
	mktemp $1_XXXXX -t -u
}

function HELP(){

	cat <<HELP

Usage: $PROGNAME link output [<optional-arguments>]
Options:
  -c, --caption  LANG        Set Caption Language [2+ letters], e.g en, ja, en-US
  -s, --size     HEIGHT      Set height of video. e.g 720 for 720p
  -f, --from     TIME        Set where to start cutting video. e.g 5:55
  -F, --format   FORMAT      Set yt-dlp -f $FORMAT. e.g 22
  -t, --to       TIME        Set where to stop cutting video, overrides -d
  -d, --duration TIME        Duration of video. e.g 1:12
  -e, --ext      EXTENSION   File extension, default: "mp4"
  -h, --help                 Print this help
Example:
$PROGNAME https://youtu.be/v1POP-m76ac /sdcard/outputfile -c ja -f 22.1 -d 15.08
HELP
}


link=''
out=''

while [ $OPTIND -le "$#" ];
do
	if getopts c:f:s:t:hd:o:F:e: FLAG; then
		case $FLAG in 
			s)
				height=$(( $OPTARG - 5 ))
				;;
			F) 
				format=$OPTARG
				;;
			f) 
				from=$(get_seconds $OPTARG)
				;;
			d)
				duration=$(get_seconds $OPTARG )
				;;
			t)
				to=$( get_seconds $OPTARG )
				;;
			o)
				out=$OPTARG
				;;
			c)
				sublang=$OPTARG
				;;
			e)
				ext=$OPTARG
				;;
			h|*)
				HELP
				exit
				;;
			\?)
				echo $OPTARG $OPTIND
				link=$OPTARG
				;;
		esac
	else
		arg="${!OPTIND}"
		[[ -z $link ]] && link=$arg arg=''
		[[ ! -z $arg ]]  && [[ -z $out ]] && out="$arg" arg=5
	        ((OPTIND++))
	fi
done
shift $((OPTIND - 1))



if [ -z $out ]; then
	log specify output path
	HELP
	exit
fi
if [ -z $link ]; then
	log specify video link
	HELP
	exit
fi

from=${from:=$FROM}
if [ ! -z $to ] && [ -z $duration ]; then
	duration=$( calc $to - $from )
fi

duration=${duration:=$DURATION}
height=${height:=$HEIGHT}
ext=${ext:=$EXT}
if [ -z $format ]; then
	format="bestvideo[height<=$height],bestaudio"
fi
to=$( calc $duration + $from )

log Downloading $link from $(get_hhmmss $from) to $(get_hhmmss $to ), duration: $duration, format: $format


links=( $( yt-dlp -gf $format  $link ) )


declare -p links > /dev/null


video=${links[0]}
audio=${links[1]}

temp=$(get_temp ${out[0]##*/})

if [ $? -ne 0 ]; then
	log Failed to get link
	exit 1
fi


function print_bar(){
	d="################################################################################################################################################################"
	width=$COLUMNS
	size=$(( $width - 27 - 9))
	fsize=$3
	progress=$(numfmt --format="%3.1f" $1)
	c=$( calc 100 / $size )
	dd=$( calc "int($1 / $c)" )
	cc=$( calc "int($size - $dd)" )
	ee=$(( 4 - ${#1} ))
	f=$(get_hhmmss $2 )
	printf "[%.*s%*s] %*s%s | %s | %s\r" $dd $d $cc "" $ee "" $progress% $fsize $f
}


function ffmpeg2(){
	shopt -s checkwinsize; (:);
	extras="-progress - -hide_banner"
	#overwrite existing files
	extras="$extras -y"
	log transcoding...
	duration_=""
	real=0
	filesize=0
	ffmpeg $extras "$@" 2>&1 |
	while read -r line; do
        field=$(echo $line|cut -d "=" -f1)
        value=$(echo $line|cut -d "=" -f2)
        case $field in
            progress)
                if [ "$value" = end ]; then
                    print_bar 100 $real $filesize
                    echo -ne "\nCOMPLETED; size: $filesize, duration: $real\n"
                fi
                ;;
            out_time)
                out_time=$value
                real=$(get_seconds $out_time)
                percentage=$(calc "100 * $real / $duration" )
                print_bar $percentage $real $filesize
                ;;
			total_size)
                filesize=$(numfmt --to=iec --format="%6.1f" $value)
                print_bar $percentage $real $filesize
                ;;
            \?)
                ;;
        esac
	done
}





if [ -z $audio ]; then
	ffmpeg2 -ss $from -i "$video" -t $duration $out.$ext
else
	ffmpeg2 -ss $from -i "$video" -ss $from -i "$audio" -map 0:v -map 1:a -t $duration $out.$ext
fi


if [ ! -z $sublang ]; then
	log Writing subtitles to $out
	yt-dlp --skip-download --write-sub --sub-lang $sublang $link --sub-format best --convert-subs ass --output $out
	subfile=$out.$sublang.ass
	if [ -f $subfile ]; then
		ls $out*
		ffmpeg -v quiet -i "$subfile" -ss $from -t $duration $temp.ass
		log Embedding subtitles into video
		ffmpeg2 -i $out.$ext -vf ass="$temp.ass" -c:a copy $out-captioned.$ext
	else
		log "selected caption '$sublang' does not exist"
		yt-dlp --list-subs $link
	fi
fi

termux-media-scan -r "$(dirname $out)"
