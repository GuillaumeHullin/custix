#!/usr/bin/env ksh
SCRIPT_NAME=$(basename $0)
SCRIPT_DIR=$(dirname $0)
SCRIPT_CACHE=${SCRIPT_DIR}/tmp
SCRIPT_CACHE_TTL=0
TIMESTAMP=`date '+%s'`

resource=${1:-full}
property=${2}

refresh_cache() {
    [[ -d ${SCRIPT_CACHE} ]] || mkdir -p ${SCRIPT_CACHE}
    file=${SCRIPT_CACHE}/${SCRIPT_NAME%.*}.json
    if [[ $(( `stat -c '%Y' "${file}" 2>/dev/null`+60*${SCRIPT_CACHE_TTL} )) -le ${TIMESTAMP} ]]; then
	regex="(Not Specified|Not Present)"
	dmi=`sudo dmidecode`
	meminfo=`cat /proc/meminfo`
	cpuinfo=`lscpu`

	dmi_system=`echo "${dmi}" | sed '/^System Information/, /Handle.*/!d'`
	dmi_chassis=`echo "${dmi}" | sed '/^Chassis Information/, /Handle.*/!d'`

	vendor=`echo "${dmi_system}"|grep "Manufacturer:"|awk '{print $2}'|awk '{$1=$1};1'`
	sku=`echo "${dmi_system}"|grep "SKU Number:"|awk -F ':' '{print $2}'|awk '{$1=$1};1'`
	serial=`echo "${dmi_system}"|grep "Serial Number:"|awk -F ':' '{print $2}'|awk '{$1=$1};1'`
	model=`echo "${dmi_system}"|grep "Product Name:"|awk -F ':' '{print $2}'|awk '{$1=$1};1'`
	chassis_type=`echo "${dmi_chassis}"|grep "Type:"|awk -F ':' '{print $2}'|awk '{$1=$1};1'`
	if [[ ${vendor} =~ (QEMU|VMware.*) ]]; then
            type='Virtual'
	else
            type='Physical'
	fi
	chassis[0]="${vendor}"
        chassis[1]="${model}"
        chassis[2]="${serial}"
        chassis[3]="${chassis_type}"
        for index in ${!chassis[@]}; do
            chassis[${index}]=`echo "${chassis[${index}]}" | sed -E "s:${regex}::g"`
        done
        chassis=`echo "${chassis[@]}"`
	memory=`echo "${meminfo}" | grep "^MemTotal:" | awk -F ':' '{print $2}' \
		     | awk '{a=$1 * 1024; print a}'` 
        swap=`echo "${meminfo}" | grep "^SwapTotal:" | awk -F ':' '{print $2}' \
		   | awk '{a=$1 * 1024;print a}'`
	cpu_count=`echo "${cpuinfo}" | grep "^CPU(s):" | awk -F ':' '{print $2}' | awk '{$1=$1};1'`
	cpu_arch=`echo "${cpuinfo}" | grep "^Architecture:" | awk -F ':' '{print $2}' | awk '{$1=$1};1'`
	cpu_model=`echo "${cpuinfo}" | grep "^Model name:" | awk -F ':' '{print $2}' | awk '{$1=$1};1'`
	cpu_sockets=`echo "${cpuinfo}" | grep "^Socket(s):" | awk -F ':' '{print $2}' | awk '{$1=$1};1'`
	cpu_vendor=`echo "${cpuinfo}" | grep "^Vendor ID:" | awk -F ':' '{print $2}' | awk '{$1=$1};1'`
	cpu_cores_per_socket=`echo "${cpuinfo}" | grep "^Core(s) per socket:" \
				   | awk -F ':' '{print $2}' | awk '{$1=$1};1'`
	cpu_threads_per_core=`echo "${cpuinfo}" | grep "^Thread(s) per core:" \
				   | awk -F ':' '{print $2}' | awk '{$1=$1};1'`
	hv_vendor=`echo "${cpuinfo}" | grep "^Hypervisor vendor:" | awk -F ':' '{print $2}' \
			| awk '{$1=$1};1'`
	virt_type=`echo "${cpuinfo}" | grep "^Virtualization type:" | awk -F ':' '{print $2}' \
			| awk '{$1=$1};1'`

	json_raw=`lsblk -d -ibo NAME,SIZE,VENDOR,SUBSYSTEMS,SERIAL -J | jq . 2>/dev/null`
	json_keys=(
	  'vendor' 'type' 'model' 'sku' 'chassis' 'serial' 'memory' 'swap' 'cpu_count' 'cpu_arch'
	  'cpu_model' 'cpu_sockets' 'cpu_vendor' 'cpu_cores_per_socket' 'cpu_threads_per_core'
	  'hv_vendor' 'virt_type'
	)
	for key in ${json_keys[@]}; do
            eval value=\${$key}
	    json_raw=`echo "${json_raw}" | jq ".${key}=\"${value}\"" 2>/dev/null`
	done
        echo "${json_raw}" | jq -S . 2>/dev/null > ${file}
    fi
    echo "${file}"
}
json=$(refresh_cache)
res=`jq -r ".${resource/full/}" ${json}`

echo "${res:-0}"
exit ${rcode:-0}