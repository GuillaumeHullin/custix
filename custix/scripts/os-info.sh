#!/usr/bin/env ksh
SCRIPT_NAME=$(basename $0)
SCRIPT_DIR=$(dirname $0)
SCRIPT_CACHE=${SCRIPT_DIR}/tmp
SCRIPT_CACHE_TTL=10
TIMESTAMP=`date '+%s'`

resource=${1:-full}
property=${2}

refresh_cache() {
    [[ -d ${SCRIPT_CACHE} ]] || mkdir -p ${SCRIPT_CACHE}
    file=${SCRIPT_CACHE}/${SCRIPT_NAME%.*}.json
    if [[ $(( `stat -c '%Y' "${file}" 2>/dev/null`+60*${SCRIPT_CACHE_TTL} )) -le ${TIMESTAMP} ]]; then
        uname_sr=`uname -sr 2>/dev/null`
	family=`echo ${uname_sr} | awk '{print $1}'`
        kernel=`echo ${uname_sr} | awk '{print $2}'`
        boottime=`cat /proc/uptime 2>/dev/null | awk '{print $1}'`
        if [[ ${family} == 'Linux' ]]; then
	    release=`lsb_release -sd 2>/dev/null`
            distro=`lsb_release -si 2>/dev/null`
            if [[ ${distro} =~ (Ubuntu|Debian) ]]; then
		updates_raw=`apt-get -s upgrade`
		updates_security=`echo "${updates_raw}" | grep -ci ^inst.*security | tr -d '\n'`
		updates_normal=`echo "${updates_raw}" | grep -iPc '^Inst((?!security).)*$' | tr -d '\n'`
		updates='{"normal": '${updates_normal}', "security": '${updates_security}'}'
		json_raw=`echo "${json_raw:-{}}" | jq ".updates=${updates}" 2>/dev/null`
	    fi
            filesystems='[ '
            while read line; do
		eval ${line}
		[[ -z ${MOUNTPOINT} ]] && continue
		filesystems+="{"
		filesystems+="\"name\": \"${NAME}\",\"mountpoint\": \"${MOUNTPOINT}\","
		filesystems+="\"size\": ${SIZE},\"fstype\": \"${FSTYPE}\""
		filesystems+="},"
		if [[ ${MOUNTPOINT} == '/' ]]; then
                    if ! [[ ${NAME} =~ (sda|vda|sdb)[1-9] ]]; then
			NAME="mapper/`echo "${NAME}" | sed 's/(.*).*//'`"
                    fi
                    fsroot_creation=`tune2fs -l /dev/${NAME} | grep 'Filesystem created:' \
                                  | sed 's/Filesystem created://' | awk '{$1=$1};1'`
                    installed=`date "+%s" -d "${fsroot_creation}"`
		fi
            done < <(lsblk -ibo NAME,MOUNTPOINT,SIZE,FSTYPE -P)
            filesystems="${filesystems%?} ]"
            json_raw=`echo "${json_raw:-{}}" | jq ".filesystems=${filesystems}" 2>/dev/null`
	fi
        # IFS=":" APPS=(${AMANA_APPS})
        # for app in ${APPS[@]}; do
        #     if [[ ${app} == 'springboot' ]]; then
	# 	springboot=`/etc/init.d/spring-boot list json id name desc version 2>/dev/null`
	# 	json_raw=`echo "${json_raw:-{}}" | jq ".apps.springboot=${springboot}" 2>/dev/null`
	#     elif [[ ${app} == 'gunicorn' ]]; then
	# 	gunicorn=`/etc/init.d/gunicorn list json id name desc version 2>/dev/null`
	# 	json_raw=`echo "${json_raw:-{}}" | jq ".apps.gunicorn=${gunicorn}" 2>/dev/null`
        #     elif [[ ${app} == 'mysql' ]]; then
	# 	db_count=`/etc/zabbix/scripts/agentd/mysbix/mysbix.sh -s db_count 2>/dev/null`
	# 	my_version=`/etc/zabbix/scripts/agentd/mysbix/mysbix.sh -s version 2>/dev/null`
	# 	mysql="{\"version\": \"${my_version}\", \"databases\": ${db_count}}"
	# 	json_raw=`echo "${json_raw:-{}}" | jq ".apps.mysql=${mysql}" 2>/dev/null`
        #     fi
        # done
	json_keys=(
	    'family'
	    'release'
            'boottime'
            'distro'
            'installed'
	)
	for key in ${json_keys[@]}; do
            eval value=\${$key}
	    json_raw=`echo "${json_raw:-{}}" | jq ".${key}=\"${value}\"" 2>/dev/null`
	done
        echo "${json_raw}" | jq . 2>/dev/null > ${file}
    fi
    echo "${file}"
}
json=$(refresh_cache)
res=`jq -r ".${resource/full/}" ${json}`

echo "${res:-0}"
exit ${rcode:-0}