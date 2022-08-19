#!/bin/sh

# プレーヤ一覧を取得する
# 入力:なし
# 出力:プレーヤ一覧(PLAYERS)
function get_target_player_list(){

    local LEVEL=${1}
    local DROP_INTERVAL=${2}
    RESULT_LEVEL_X_CSV="result_level_${LEVEL}.csv"
    rm -f ${RESULT_LEVEL_X_CSV}

    # プレーヤ用配列
    PLAYERS=()
    #PLAYERS=(
    #    "isshy-you@ish04e"
    #    "isshy-you@ish04f"
    #    "isshy-you@ish05a"
    #    "isshy-you@ish05b"
    #    "isshy-you@ish05c"
    #    "isshy-you@ish05d"
    #    "isshy-you@ish05f"
    #    "isshy-you@ish05g3"
    #    "isshy-you@ish05g6"
    #    "isshy-you@ish05h3"
    #    "seigot@master"
    #)

    # 入力ファイルを取得
    wget https://raw.githubusercontent.com/seigot/tetris_score_server/main/log/${RESULT_LEVEL_X_CSV}

    # 入力ファイルから対象Playerを取得して配列に格納する
    TARGET_LIST=()
    TARGET_LIST_UNIQ=()
    #COMPARE_DATE=`date --date '8 week ago' +"%Y%m%d"`
    COMPARE_DATE=`date --date '10 week ago' +"%Y%m%d"`

    while read -r line
    do
        # skip first line
        CHECK_STR=`echo $line | cut -d, -f1`
        if [ "$CHECK_STR" == "DATETIME" ]; then
            continue
        fi

	# check drop interval value
        DROP_INTERVAL_VAL=`echo $line | cut -d, -f7 | sed -e 's/ //g'`
	echo "DROP_INTERVAL_VAL:${DROP_INTERVAL_VAL}"
	echo "DROP_INTERVAL:${DROP_INTERVAL}"
        if [ "${DROP_INTERVAL_VAL}" != "${DROP_INTERVAL}" ]; then
	    echo "${DROP_INTERVAL_VAL} != ${DROP_INTERVAL}"
            continue
	fi

	# check if use machine learning mode
	# currently, skip..
        VALUE_MODE=`echo $line | cut -d, -f8 | sed -e 's/ //g'`
	echo "VALUE_MODE:${VALUE_MODE}"
        if [ "${VALUE_MODE}" != "default" -a "${VALUE_MODE}" != "-" ]; then
	    echo "${VALUE_MODE} != default"
	    echo "skip.."
            continue
	fi

        # skip past line
        TARGET_DATE=`echo $line | cut -d, -f1 | cut -d_ -f1 | sed -E 's/[\/|\_|\:]//g'`
        if [ $TARGET_DATE -lt $COMPARE_DATE ]; then
            continue
        fi

        # get target string
        TARGET_UNAME=`echo ${line} | cut -d, -f2 | cut -d/ -f4`
        TARGET_BRANCH=`echo ${line} | cut -d, -f3 | sed -e 's/ //g'`
        TARGET_STR="${TARGET_UNAME}@${TARGET_BRANCH}"
        TARGET_LIST+=(${TARGET_STR})
    done < ${RESULT_LEVEL_X_CSV}

    # 重複を削除
    i=0
    while read -r x; do
          TARGET_LIST_UNIQ[i++]="$x"
    done < <(printf '%s\n' "${TARGET_LIST[@]}" | sort -u)
    PLAYERS=(${TARGET_LIST_UNIQ[@]})
    echo ${PLAYERS[@]}
}

# Player一覧を結果出力用にファイル出力する
# 入力:プレーヤ一覧(PLAYERS)
# 出力:プレーヤ一覧(結果出力用)(PLAYER_TEXT)
PLAYER_TEXT="player.txt"
function printPlayerList() {
    echo "--- PlayerList"
    PlayerNo=0
    echo "PlayerNo,Player" > ${PLAYER_TEXT}
    for player in ${PLAYERS[@]}; do
	PlayerNo=`expr $PlayerNo + 1`
	echo "$PlayerNo,$player"
	echo "$PlayerNo,$player" >> ${PLAYER_TEXT}
    done
}

# プレーヤ一覧から、総当たり戦を実施するための組み合わせ一覧表を作成する
# 入力:プレーヤ一覧(PLAYERS)
# 出力:対戦の組み合わせ一覧表(COMBINATION_LIST)
function get_combination_list() {
    COMBINATION_LIST=()
    echo "--- CombinationList"
    N=`echo ${#PLAYERS[*]}`
    N=`expr ${N} - 1`
    for i in `seq 0 ${N}`; do
	for j in `seq 0 ${N}`; do
	    STR="${i}_${j}"
            #echo ${STR}
	    COMBINATION_LIST+=(${STR})
	done
    done
}

# 対戦する
# 入力:
# 出力:
RESULT_TEXT="result.txt"
RESULT_MATRIX_TEXT="result_matrix.txt"
CURRENT_SCORE_TEXT="current_score.txt"
function do_tetris(){
    # parameter declaration
    local DATETIME="$1"
    local REPOSITORY_URL="$2"
    local BRANCH="$3"
    local LEVEL="$4"
    local DROP_INTERVAL="$5"
    local RANDOM_SEED="$6"
    local GAME_TIME="180"
    #GAME_TIME="180" # debug value
    local BLOCKNUMMAX="-1"
    local PRE_COMMAND="cd ~ && rm -rf tetris && git clone ${REPOSITORY_URL} -b ${BRANCH} && cd ~/tetris && pip3 install -r requirements.txt"
    local DO_COMMAND="cd ~/tetris && export DISPLAY=:1 && python3 start.py -l ${LEVEL} -t ${GAME_TIME} -d ${DROP_INTERVAL} -r ${RANDOM_SEED} --BlockNumMax ${BLOCKNUMMAX} && jq . result.json"
    local POST_COMMAND="cd ~/tetris && jq . result.json"

    local TMP_LOG="tmp.json"
    local TMP2_LOG="tmp2.log"
    local OUTPUTJSON="output.json"
    local CONTAINER_NAME="tetris_docker"

    # run docker with detached state
    RET=`docker ps -a | grep ${CONTAINER_NAME} | wc -l`
    if [ $RET -ne 0 ]; then
	docker stop ${CONTAINER_NAME}
	docker rm ${CONTAINER_NAME}
    fi
    docker run -d --name ${CONTAINER_NAME} -p 6080:80 --shm-size=512m seigott/tetris_docker

    # exec command
    docker exec ${CONTAINER_NAME} bash -c "${PRE_COMMAND}"
    if [ $? -ne 0 ]; then
	return 1
    fi

    # check if --BlockNumMax N option is available 
    TARGET_HASHID="23427b6548e7d168d2c740a258879bdedf1159ed" # add --BlockNumMax N option to start.py to specify block number to fin…
    docker exec ${CONTAINER_NAME} bash -c "cd ~/tetris && git branch --contains ${TARGET_HASHID}"
    RET=$?
    if [ $RET -ne 0 ]; then
	# if unavaiable, use old command
	echo "not contains hashid: ${TARGET_HASHID}"
	DO_COMMAND="cd ~/tetris && export DISPLAY=:1 && python3 start.py -l ${LEVEL} -t ${GAME_TIME} -d ${DROP_INTERVAL} -r ${RANDOM_SEED} && jq . result.json"
    else
	# if avaiable
	if [ "${DROP_INTERVAL}" == "1000" ]; then
	    # DROP_INTERVAL=1000の場合に処理効率化ができないか確認する
	    BLOCKNUMMAX="180"
	    DROP_INTERVAL="1"
	    DO_COMMAND="cd ~/tetris && export DISPLAY=:1 && python3 start.py -l ${LEVEL} -t ${GAME_TIME} -d ${DROP_INTERVAL} -r ${RANDOM_SEED} --BlockNumMax ${BLOCKNUMMAX} && jq . result.json"
	fi
    fi

    # disconnect network to disable outbound connection for security
    docker network disconnect bridge ${CONTAINER_NAME}
    
    # do command
    echo "DO_COMMAND:${DO_COMMAND}"
    docker exec ${CONTAINER_NAME} bash -c "${DO_COMMAND}"
    if [ $? -ne 0 ]; then
	return 1
    fi
    # get result
    docker exec ${CONTAINER_NAME} bash -c "${POST_COMMAND}" > ${TMP_LOG}

    # check if max score
    CURRENT_SCORE=`jq .judge_info.score ${TMP_LOG}`
    echo ${CURRENT_SCORE} > ${CURRENT_SCORE_TEXT}
    return 0
}

# 対戦する
# 入力:対戦情報(Player,level,etc)
# 出力:対戦結果
function do_battle(){
    local PLAYER1_=${1}
    local PLAYER2_=${2}
    local LEVEL_=${3}
    local DROP_INTERVAL=${4}
    local RANDOM_SEED=${RANDOM}
    if [ "${LEVEL_}" == "1" ]; then
	RANDOM_SEED=0
    fi

    #echo "${PLAYER1}, ${PLAYER2}"
    PLAYER1_NAME=`echo ${PLAYER1_} | cut -d'@' -f1`
    PLAYER1_BRANCH=`echo ${PLAYER1_} | cut -d'@' -f2`
    PLAYER2_NAME=`echo ${PLAYER2_} | cut -d'@' -f1`
    PLAYER2_BRANCH=`echo ${PLAYER2_} | cut -d'@' -f2`
    ## Player1
    do_tetris 0 "https://github.com/${PLAYER1_NAME}/tetris" "${PLAYER1_BRANCH}" "${LEVEL_}" "${DROP_INTERVAL}" "${RANDOM_SEED}"
    RET=$?
    if [ $RET -ne 0 ]; then
	PLAYER1_SCORE=0
    else
	PLAYER1_SCORE=`cat ${CURRENT_SCORE_TEXT}`
    fi
    ## Player2
    do_tetris 0 "https://github.com/${PLAYER2_NAME}/tetris" "${PLAYER2_BRANCH}" "${LEVEL_}" "${DROP_INTERVAL}" "${RANDOM_SEED}"
    RET=$?
    if [ $RET -ne 0 ]; then
	PLAYER2_SCORE=0
    else
	PLAYER2_SCORE=`cat ${CURRENT_SCORE_TEXT}`
    fi

    # output result
    TMP_NO=`tail -1 ${RESULT_TEXT} | cut -d, -f1`
    GameNo=`expr $TMP_NO + 1`
    RET=$?
    if [ $RET -ge 2 ];then
	# not a number
        GameNo=1
    fi
    echo "${GameNo},${PLAYER1_}:${PLAYER1_SCORE},${PLAYER2_}:${PLAYER2_SCORE}" >> ${RESULT_TEXT}

    if [ $PLAYER1_SCORE -gt $PLAYER2_SCORE ]; then
	return 0 # win
    elif [ $PLAYER1_SCORE -lt $PLAYER2_SCORE ]; then
	return 1 # lose
    else
	return 2 # draw
    fi
}

# 組み合わせ一覧表の順番に総当たり戦をする
# 入力:対戦の組み合わせ一覧表(COMBINATION_LIST)
# 出力:対戦結果の配列(RESULT_LIST)
function do_battle_main() {

    local LEVEL=${1}
    local DROP_INTERVAL=${2}

    echo ${COMBINATION_LIST[@]}
    RESULT_LIST=()

    #echo -n > ${RESULT_TEXT}
    echo "GameNo,player1,player2" > ${RESULT_TEXT}
    
    for i in ${COMBINATION_LIST[@]}; do

        # 変数を取得
	PLAYER1_NUM=`echo ${i} | cut -d'_' -f1`
	PLAYER2_NUM=`echo ${i} | cut -d'_' -f2`
	PLAYER1=${PLAYERS[${PLAYER1_NUM}]}
	PLAYER2=${PLAYERS[${PLAYER2_NUM}]}
	echo "${PLAYER1_NUM}:${PLAYER1}, ${PLAYER2_NUM}:${PLAYER2}"

        # 対戦不要の組み合わせの場合
        # 結果を取得して対戦はスキップする
	if [ ${PLAYER1_NUM} -ge ${PLAYER2_NUM} ]; then
	    RESULT="-"
	    RESULT_LIST+=(${RESULT})
	    continue
	fi

        # 対戦必要な組み合わせの場合
        # ここで対戦する(PLAYER1 vs PLAYER2) -->
	do_battle "${PLAYER1}" "${PLAYER2}" "${LEVEL}" "${DROP_INTERVAL}"
	RET=$?
	if [ $RET -eq 0 ]; then
	    RESULT="W"
	elif [ $RET -eq 1 ]; then
	    RESULT="L"
	else
	    RESULT="D"
	fi
        # <---- ここまで対戦

        # 対戦結果を格納する
	RESULT_LIST+=(${RESULT})
    done
}

# 対戦結果の配列から結果表を出力する
# 入力:対戦結果の配列(RESULT_LIST),対戦の組み合わせ一覧表(COMBINATION_LIST)
# 出力:結果表(RESULT_MATRIX_TEXT)
function get_result() {
    # show result list
    echo "--- ResultList"
    echo ${RESULT_LIST[@]}
    echo "--- Result"
    count=0

    # output header string
    #echo -n > ${RESULT_MATRIX_TEXT}
    echo -n "you\opponent PlayerNo," > ${RESULT_MATRIX_TEXT}
    N=`echo ${#PLAYERS[*]}`
    for i in `seq 1 ${N}`; do
	echo -n "${i}," >> ${RESULT_MATRIX_TEXT}
    done
    echo "" >> ${RESULT_MATRIX_TEXT}

    # main process
    for i in ${COMBINATION_LIST[@]}; do

	PLAYER1_NUM=`echo ${i} | cut -d'_' -f1`
	PLAYER2_NUM=`echo ${i} | cut -d'_' -f2`
	RESULT=${RESULT_LIST[${count}]}

        # 対象PLAYERの名前を出力する
	TMP_NUM=`expr $count % ${#PLAYERS[@]}`
	if [ "${TMP_NUM}" == "0" ]; then
	    PLAYER1=${PLAYERS[${PLAYER1_NUM}]}
	    echo -n "${PLAYER1}," >> ${RESULT_MATRIX_TEXT}
	fi
	
        # 結果を出力
	if [ ${PLAYER1_NUM} -lt ${PLAYER2_NUM} ]; then
	    echo -n "${RESULT}," >> ${RESULT_MATRIX_TEXT}
	elif [ ${PLAYER1_NUM} -gt ${PLAYER2_NUM} ]; then
            # 既存の結果を再利用(総当たり表の反対側の要素を取得)
	    AA=`expr ${count} / ${#PLAYERS[@]}`
	    BB=`expr ${count} % ${#PLAYERS[@]}`
	    CC=`expr ${BB} \* ${#PLAYERS[@]} + ${AA}`
	    RESULT=${RESULT_LIST[${CC}]}
	    if [ "${RESULT}" == "W" ]; then
		echo -n "L," >> ${RESULT_MATRIX_TEXT}
	    elif [ "${RESULT}" == "L" ]; then
		echo -n "W," >> ${RESULT_MATRIX_TEXT}
	    else
		echo -n "D," >> ${RESULT_MATRIX_TEXT} # draw
	    fi
	else
	    echo -n "-," >> ${RESULT_MATRIX_TEXT}
	fi

        # PLAYERS分だけループ処理したら改行する
	count=`expr $count + 1`
	TMP_NUM=`expr $count % ${#PLAYERS[@]}`
	if [ "${TMP_NUM}" == "0" ]; then
	    echo "" >> ${RESULT_MATRIX_TEXT}
	fi
    done
    cat ${RESULT_MATRIX_TEXT}
}

# 結果を更新する
# 入力:結果情報
# 出力:なし
function upload_result() {

    local LEVEL=${1}
    local DROP_INTERVAL=${2}

    today=$(date +"%Y%m%d%H%M")
    RESULT_MD="result_level${LEVEL}_${today}_${DROP_INTERVAL}.md"
    RESULT_MD_LATEST="result_level${LEVEL}_${DROP_INTERVAL}.md"
    echo -n "" > ${RESULT_MD}
    echo "Date: ${today}  " >> ${RESULT_MD}
    echo "Level: ${LEVEL}  " >> ${RESULT_MD}
    echo "DropInterval: ${DROP_INTERVAL}  " >> ${RESULT_MD}

    echo "--- upload result"

    echo "--- player.txt"
    cat ${PLAYER_TEXT}
    echo "## player list" >> ${RESULT_MD}
    cat ${PLAYER_TEXT} | csvtomd >> ${RESULT_MD}

    echo "--- result_matrix.txt"
    cat ${RESULT_MATRIX_TEXT}
    echo "## result(matrix)" >> ${RESULT_MD}
    echo "W:win, L:lose, D:draw" >> ${RESULT_MD}
    cat ${RESULT_MATRIX_TEXT} | sed -e "s/,\$//" | csvtomd >> ${RESULT_MD} >> ${RESULT_MD}

    echo "--- result summary"
    echo "## result(summary)" >> ${RESULT_MD}
    cat ${RESULT_MATRIX_TEXT} | tail -n+2 | python3 get_result_summary.py | csvtomd >> ${RESULT_MD}

    echo "--- result.txt"
    cat ${RESULT_TEXT}
    echo "## result(detail)" >> ${RESULT_MD}
    cat ${RESULT_TEXT} | csvtomd >> ${RESULT_MD}

    # copy as latest file
    cp ${RESULT_MD} ${RESULT_MD_LATEST}

    # git add/commit/push
    git pull
    git add ${RESULT_MD}
    git add ${RESULT_MD_LATEST}
    git commit -m "update"
    git push
}

# main処理
function main(){
    local LEVEL=${1}
    local DROP_INTERVAL=${2}

    get_target_player_list ${LEVEL} ${DROP_INTERVAL}
    printPlayerList
    get_combination_list
    do_battle_main ${LEVEL} ${DROP_INTERVAL}
    get_result
    upload_result ${LEVEL} ${DROP_INTERVAL}
}

PRE_DATE="00000000"
while true
do
    # 日付が変わったら実行する
    # check date
    CURRENT_DATE=`date +"%Y%m%d"`
    if [ ${CURRENT_DATE} -eq ${PRE_DATE} ];then
        echo "date not updated. ${CURRENT_DATE}"
        sleep 900
        continue
    fi
    echo "date updated !! ${PRE_DATE} --> ${CURRENT_DATE}"
    PRE_DATE=${CURRENT_DATE}

    # main
    main 1 1000
    main 2 1000
    main 3 1000
    main 3 1
done

