#!/bin/sh

#A server setup script (alpha)
server_num=0
fastd_secret=""
wan_iface="eth0"

#abort script on first error
set -e
set -u

echo "Please enter the number of the server: "
read server_num
[ $server_num -gt 0 ] || exit 1


is_running() {
  pidof "$1" > /dev/null || return $?
}

is_installed() {
  which "$1" > /dev/null || return $?
}

sha256check() {
	local file="$1" hash="$2"
	if [ "$(sha256sum $file | cut -b 1-64)" != "$hash" ]; then
		echo "(E) Hash mismatch: $file"
		exit 1
	fi
}

get_mac() {
	local mac=`cat /sys/class/net/$1/address`

	# translate to local administered mac
	a=${mac%%:*} #cut out first hex
	a=$((0x$a ^ 2)) #invert second least significant bit
	a=`printf '%02x\n' $a` #convert back to hex
	echo "$a:${mac#*:}" #reassemble mac
}

#we like to have a constant MAC
#to be able to track a node on the map.
mac="$(get_mac $wan_iface)"

if [ ! -f /root/scripts/update.sh ]; then
	echo "(I) Create /root/scripts/"
	cp -rf scripts /root/
fi

if ! is_installed "lighttpd"; then
	echo "(I) Install lighttpd"
	apt-get install --assume-yes lighttpd
fi

if [ ! -f /etc/lighttpd/lighttpd.conf ]; then
	echo "(I) Create /etc/lighttpd/lighttpd.conf"
	cp etc/lighttpd/lighttpd.conf /etc/lighttpd/
	sed -i "s/fdef:17a0:ffb1:300::1/fdef:17a0:ffb1:300::$server_num/g" /etc/lighttpd/lighttpd.conf
fi

if ! id www-data >/dev/null 2>&1; then
	echo "(I) Create user/group www-data for lighttpd."
	useradd --system --no-create-home --user-group --shell /bin/false www-data
fi

if [ ! -d /var/www/status ]; then
	echo "(I) Create /var/www/status"
	mkdir -p /var/www/status
	cp -r var/www/status /var/www/

	#set server name/number in status page
	sed -i "s/vpn0/vpn$server_num/g" /root/scripts/status_page_create.sh
	chown -R www-data:www-data var/www/status
fi

if [ ! -d /var/www/map ]; then
	echo "(I) Create /var/www/map"
	apt-get install --assume-yes make
	git clone https://github.com/freifunk-bielefeld/ffmap-d3.git
	cd ffmap-d3
	make
	mkdir -p /var/www/map
	cp -r www/* /var/www/map/
	cd ..
	rm -rf ffmap-d3
	chown -R www-data:www-data /var/www/map
fi

if [ ! -d /var/www/counter ]; then
	echo "(I) Create /var/www/counter"
	mkdir -p /var/www/counter
	cp -r var/www/counter /var/www/
	chown -R www-data:www-data var/www/counter
fi

if [ -z "$(cat /etc/crontab | grep '/root/scripts/update.sh')" ]; then
	echo "(I) Add entry to /etc/crontab"
	echo '*/5 * * * * root /root/scripts/update.sh' >> /etc/crontab
fi

if ! is_installed "alfred"; then
	echo "(I) Install batman, batctl and alfred."
	VERSION=2014.3.0
	apt-get install --assume-yes wget build-essential linux-headers-$(uname -r) pkg-config libnl-3-dev

	wget --no-check-certificate http://downloads.open-mesh.org/batman/releases/batman-adv-$VERSION/batman-adv-$VERSION.tar.gz
	sha256check "batman-adv-$VERSION.tar.gz" "7ffb2bfca558f1078b2bafef8d5304760054567dfe39d2445bf4c25ee72faae7"
	tar -xzf batman-adv-$VERSION.tar.gz
	cd batman-adv-$VERSION/
	make
	make install
	cd ..
	rm -rf batman-adv-$VERSION*

	wget --no-check-certificate http://downloads.open-mesh.org/batman/releases/batman-adv-$VERSION/batctl-$VERSION.tar.gz
	sha256check "batctl-2014.3.0.tar.gz" "5885a2376f0bd2a2addb89b9366265d9a9c2ec0e4f5906317b0baa0514983e84"
	tar -xzf batctl-$VERSION.tar.gz
	cd batctl-$VERSION/
	make
	make install
	cd ..
	rm -rf batctl-$VERSION*

	wget --no-check-certificate http://downloads.open-mesh.org/batman/stable/sources/alfred/alfred-$VERSION.tar.gz
	sha256check "alfred-2014.3.0.tar.gz" "bc11c17409df13c788bb26180a2d4a23d9ae2430b60d72eedeecf8f148a05f1a"
	tar -xzf alfred-$VERSION.tar.gz
	cd alfred-$VERSION/
	make CONFIG_ALFRED_GPSD=n 
	make CONFIG_ALFRED_GPSD=n install
	cd ..
	rm -rf alfred-$VERSION*
fi

if ! is_installed "radvd"; then
	echo "(I) Install radvd."
	apt-get install --assume-yes radvd
fi

if [ ! -f /etc/radvd.conf ]; then
	echo "(I) Configure radvd"
	cp etc/radvd.conf /etc/
	sed -i "s/fdef:17a0:ffb1:300::1/fdef:17a0:ffb1:300::$server_num/g" /etc/radvd.conf
fi

if ! is_installed "tayga"; then
	echo "(I) Install tayga."
	apt-get install --assume-yes tayga

	echo "(I) Configure tayga"
	cp -r etc/tayga.conf /etc/
	#enable tayga
	sed -i 's/RUN="no"/RUN="yes"/g' /etc/default/tayga
fi

if ! is_installed "fastd"; then
	echo "(I) Install fastd."
#	wget http://repo.universe-factory.net/debian/pool/main/libu/libuecc/libuecc0_4-1_amd64.deb
#	wget http://repo.universe-factory.net/debian/pool/main/f/fastd/fastd_14-1_amd64.deb
#	dpkg -i libuecc0_4-1_amd64.deb
#	dpkg -i fastd_14-1_amd64.deb
#	rm libuecc0_4-1_amd64.deb
#	rm fastd_14-1_amd64.deb

	apt-get install --assume-yes git cmake-curses-gui libnacl-dev flex bison libcap-dev pkg-config zip

	#install libsodium
	wget --no-check-certificate http://github.com/jedisct1/libsodium/releases/download/1.0.0/libsodium-1.0.0.tar.gz
	sha256check "libsodium-1.0.0.tar.gz" "ced1fe3d2066953fea94f307a92f8ae41bf0643739a44309cbe43aa881dbc9a5"
	tar -xvzf libsodium-1.0.0.tar.gz
	cd libsodium-1.0.0
	./configure
	make
	make install
	cd ..
	rm -rf libsodium-1.0.0*
	ldconfig

	#install libuecc
	wget --no-check-certificate http://projects.universe-factory.net/attachments/download/71 -O libuecc-4.tar.xz
	sha256check "libuecc-4.tar.xz" "8662e3e5223f17211930d7e43fefedf60492280dad32595a5b234964153bc086"
	tar xf libuecc-4.tar.xz
	mkdir libuecc_build
	cd libuecc_build
	cmake ../libuecc-4
	make
	make install
	cd ..
	rm -rf libuecc_build libuecc-4*
	ldconfig

	#install fastd
	wget --no-check-certificate http://projects.universe-factory.net/attachments/download/75 -O fastd-14.tar.xz
	sha256check "fastd-14.tar.xz" "16a49102115f4b164433e04dc14bbce43bd247a4def3a189723013f22b4fbcb2"
	tar xf fastd-14.tar.xz
	mkdir fastd_build
	cd fastd_build
	cmake ../fastd-14
	make
	make install
	cd ..
	rm -rf fastd_build fastd-14*
fi

if [ ! -f /etc/fastd/fastd.conf ]; then
	echo "(I) Configure fastd"
	cp -r etc/fastd /etc/

	if [ -z "$fastd_secret" ]; then
		echo "(I) Create Fastd private key pair. This may take a while..."
		fastd_secret=$(fastd --generate-key --machine-readable)
	fi
	echo "secret \"$fastd_secret\";" >> /etc/fastd/fastd.conf
	fastd_key=$(echo "secret \"$fastd_secret\";" | fastd --config - --show-key --machine-readable)
	echo "#key \"$fastd_key\";" >> /etc/fastd/fastd.conf
fi

if ! id nobody >/dev/null 2>&1; then
	echo "(I) Create user nobody for fastd."
	useradd --system --no-create-home --shell /bin/false nobody
fi

if ! is_installed "openvpn"; then
	echo "(I) Install openvpn."
	apt-get install --assume-yes openvpn
fi

if [ $(sysctl -n net.ipv6.conf.all.forwarding) -eq "0" ]; then
	echo "(I) Enable IPv6 forwarding"
	sysctl -w net.ipv6.conf.all.forwarding=1
fi

if ! lsmod | grep -v grep | grep "batman_adv" > /dev/null; then
  echo "(I) Start batman-adv."
  modprobe batman_adv
fi

if ! is_running "fastd"; then
  echo "(I) Start fastd."
  fastd --config /etc/fastd/fastd.conf --daemon
fi

ip addr flush dev fastd_mesh
ip link set fastd_mesh up
batctl if add fastd_mesh

ip link set bat0 down
ip link set bat0 address "$mac"
ip link set bat0 up

echo "5000" >  /sys/class/net/bat0/mesh/orig_interval
echo "0" >  /sys/class/net/bat0/mesh/multicast_mode

ip -6 addr add fdef:17a0:ffb1:300::$server_num/64 dev bat0
#ip -6 addr add 2001:bf7:1320:300::$server_num/64 dev bat0

if ! is_running "radvd"; then
  echo "(I) Start radvd."
  /etc/init.d/radvd start
fi

if ! is_running "tayga"; then
  echo "(I) Start tayga."
  /etc/init.d/tayga start
fi

if ! is_running "alfred"; then
  echo "(I) Start alfred."
  alfred -i bat0  -b bat0 -m &> /dev/null &
fi
