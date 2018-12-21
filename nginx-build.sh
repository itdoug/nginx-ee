#!/bin/bash
# -------------------------------------------------------------------------
#  Nginx-ee - Automated Nginx compilation from source
# -------------------------------------------------------------------------
# Website:       https://virtubox.net
# GitHub:        https://github.com/VirtuBox/nginx-ee
# Copyright (c) 2018 VirtuBox <contact@virtubox.net>
# This script is licensed under M.I.T
# -------------------------------------------------------------------------
# Version 3.3.3 - 2018-11-27
# -------------------------------------------------------------------------

# Check if user is root
[ "$(id -u)" != "0" ] && {
    echo "Error: You must be root to run this script, please use the root user to install the software."
    exit 1
}

# check if curl is installed
[ ! -x /usr/bin/curl ] && {
    apt-get install curl | sudo tee -a /tmp/nginx-ee.log 2>&1
}

# Checking lsb_release package
[ ! -x /usr/bin/lsb_release  ]&& {
    sudo apt-get -y install lsb-release | sudo tee -a /tmp/nginx-ee.log 2>&1
}

##################################
# Variables
##################################

NAXSI_VER=0.56
DIR_SRC=/usr/local/src
NGINX_EE_VER=3.3.3
NGINX_MAINLINE=$(curl -sL https://nginx.org/en/download.html 2>&1 | grep -E -o 'nginx\-[0-9.]+\.tar[.a-z]*' | awk -F "nginx-" '/.tar.gz$/ {print $2}' | sed -e 's|.tar.gz||g' | head -n 1 2>&1)
NGINX_STABLE=$(curl -sL https://nginx.org/en/download.html 2>&1 | grep -E -o 'nginx\-[0-9.]+\.tar[.a-z]*' | awk -F "nginx-" '/.tar.gz$/ {print $2}' | sed -e 's|.tar.gz||g' | head -n 2 | grep 1.14 2>&1)
DISTRO_VERSION=$(lsb_release -sc)
TLS13_CIPHERS="TLS13+AESGCM+AES256:TLS13+AESGCM+AES128:TLS13+CHACHA20:EECDH+CHACHA20:EECDH+AESGCM:EECDH+AES"



# install gcc-7

# Colors
CSI='\033['
CEND="${CSI}0m"
CRED="${CSI}1;31m"
CGREEN="${CSI}1;32m"

##################################
# Initial check & cleanup
##################################

# clean previous install log

echo "" >/tmp/nginx-ee.log

# detect Plesk
[ -d /etc/psa ] && {
    NGINX_PLESK=1
}

# detect easyengine
[ -d /etc/ee ] && {
    NGINX_EASYENGINE=1
    EE_VALID="YES"
}

[ ! -x /usr/sbin/nginx ] && {
    NGINX_FROM_SCRATCH=1
    echo "No Plesk or EasyEngine installation detected"
}

##################################
# Parse script arguments
##################################

while [ ${#} -gt 0 ]; do
    case "${1}" in
        --pagespeed)
            PAGESPEED="y"
        ;;
        --pagespeed-beta)
            PAGESPEED="y"
            PAGESPEED_RELEASE="1"
        ;;
        --full)
            PAGESPEED="y"
            NAXSI="y"
            RTMP="y"
        ;;
        --naxsi)
            NAXSI="y"
        ;;
        --rtmp)
            RTMP="y"
        ;;
        --latest | --mainline)
            NGINX_RELEASE="1"
        ;;
        --stable)
            NGINX_RELEASE="2"
        ;;
        *) ;;
    esac
    shift
done

##################################
# Installation menu
##################################

echo ""
echo "Welcome to the nginx-ee bash script v${NGINX_EE_VER}"
echo ""

# interactive
if [ -z "$NGINX_RELEASE" ]; then
    clear
    echo ""
    echo "Do you want to compile the latest Nginx [1] Mainline v${NGINX_MAINLINE} or [2] Stable v${NGINX_STABLE} Release ?"
    while [[ $NGINX_RELEASE != "1" && $NGINX_RELEASE != "2" ]]; do
        read -p "Select an option [1-2]: " NGINX_RELEASE
    done

    echo -e '\nDo you want Ngx_Pagespeed ? (y/n)'
    while [[ $PAGESPEED != "y" && $PAGESPEED != "n" ]]; do
        read -p "Select an option [y/n]: " PAGESPEED
    done
    if [ "$PAGESPEED" = "y" ]; then
        echo -e '\nDo you prefer the latest Pagespeed [1] Beta or [2] Stable Release ?'
        while [[ $PAGESPEED_RELEASE != "1" && $PAGESPEED_RELEASE != "2" ]]; do
            read -p "Select an option [1-2]: " PAGESPEED_RELEASE
        done
    fi
    echo -e '\nDo you want NAXSI WAF (still experimental)? (y/n)'
    while [[ $NAXSI != "y" && $NAXSI != "n" ]]; do
        read -p "Select an option [y/n]: " NAXSI
    done

    echo -e '\nDo you want RTMP streaming module (used for video streaming) ? (y/n)'
    while [[ $RTMP != "y" && $RTMP != "n" ]]; do
        read -p "Select an option [y/n]: " RTMP
    done
    echo ""
fi
##################################
# Set nginx release and modules
##################################

if [ "$NGINX_RELEASE" = "1" ]; then
    NGINX_VER="$NGINX_MAINLINE"
    NGX_HPACK="--with-http_v2_hpack_enc"
else
    NGINX_VER="$NGINX_STABLE"
    NGX_HPACK=""
fi

if [ "$RTMP" = "y" ]; then
    NGINX_CC_OPT=( [index]=--with-cc-opt='-m64 -march=native -DTCP_FASTOPEN=23 -g -O3 -fstack-protector-strong -flto -fuse-ld=gold --param=ssp-buffer-size=4 -Wformat -Werror=format-security -Wimplicit-fallthrough=0 -Wno-error=date-time -D_FORTIFY_SOURCE=2' )
    NGX_RTMP="--add-module=/usr/local/src/nginx-rtmp-module "
    RTMP_VALID="YES"
else
    if [ "$DISTRO_VERSION" == "xenial" ] && [ "$DISTRO_VERSION" == "bionic" ]; then
        NGINX_CC_OPT=( [index]=--with-cc-opt='-m64 -march=native -DTCP_FASTOPEN=23 -g -O3 -fstack-protector-strong -flto -fuse-ld=gold --param=ssp-buffer-size=4 -Wformat -Werror=format-security -Wimplicit-fallthrough=0 -fcode-hoisting -Wp,-D_FORTIFY_SOURCE=2 -gsplit-dwarf' )
    else
        NGINX_CC_OPT=( [index]=--with-cc-opt='-m64' )
    fi
    NGX_RTMP=""
    RTMP_VALID="NO"
fi

if [ "$NAXSI" = "y" ]; then
    NGX_NAXSI="--add-module=/usr/local/src/naxsi/naxsi_src "
    NAXSI_VALID="YES"
else
    NGX_NAXSI=""
    NAXSI_VALID="NO"
fi

if [ "$PAGESPEED_RELEASE" = "1" ]; then
    NGX_PAGESPEED="--add-module=/usr/local/src/incubator-pagespeed-ngx-latest-beta "
    PAGESPEED_VALID="Beta"
    elif [ "$PAGESPEED_RELEASE" = "2" ]; then
    NGX_PAGESPEED="--add-module=/usr/local/src/incubator-pagespeed-ngx-latest-stable "
    PAGESPEED_VALID="Stable"
else
    NGX_PAGESPEED=""
    PAGESPEED_VALID="NO"
fi

if [ "$NGINX_PLESK" = "1" ]; then
    NGX_USER="--user=nginx --group=nginx"
    PLESK_VALID="YES"
else
    NGX_USER=""
    PLESK_VALID="NO"
fi

if [ -z "$NGINX_EASYENGINE" ]; then
    EE_VALID="NO"
else
    EE_VALID="YES"
fi

echo "   Compilation summary : "
echo "       - Nginx release : ${NGINX_VER}"
echo "       - Pagespeed : $PAGESPEED_VALID "
echo "       - Naxsi : $NAXSI_VALID"
echo "       - RTMP : $RTMP_VALID"
echo "       - EasyEngine : $EE_VALID"
echo "       - Plesk : $PLESK_VALID"
echo ""

##################################
# Install dependencies
##################################

echo -ne '       Installing dependencies               [..]\r'
apt-get update >>/tmp/nginx-ee.log 2>&1
apt-get install -y git build-essential libtool automake autoconf zlib1g-dev \
libpcre3 libpcre3-dev libgd-dev libssl-dev libxslt1-dev libxml2-dev libgeoip-dev libjemalloc1 libjemalloc-dev \
libbz2-1.0 libreadline-dev libbz2-dev libbz2-ocaml libbz2-ocaml-dev software-properties-common sudo tar zlibc zlib1g zlib1g-dbg \
libcurl4-openssl-dev libgoogle-perftools-dev libperl-dev libpam0g-dev libbsd-dev zip unzip gnupg gnupg2 pigz libluajit-5.1-common \
libluajit-5.1-dev libmhash-dev libexpat-dev libgmp-dev autotools-dev bc checkinstall ccache curl debhelper dh-systemd libxml2 >>/tmp/nginx-ee.log 2>&1

if [ $? -eq 0 ]; then
    echo -ne "       Installing dependencies                [${CGREEN}OK${CEND}]\\r"
    echo -ne '\n'
else
    echo -e "        Installing dependencies              [${CRED}FAIL${CEND}]"
    echo -e '\n      Please look at /tmp/nginx-ee.log\n'
    exit 1
fi

##################################
# Checking install type
##################################

if [ "$NGINX_FROM_SCRATCH" = "1" ]; then

    # clone custom nginx configuration
    git clone https://github.com/VirtuBox/nginx-config.git /etc/nginx

    # create nginx temp directory
    mkdir -p /var/lib/nginx/{body,fastcgi,proxy,scgi,uwsgi}
    # create nginx cache directory
    [ ! -d /var/cache/nginx ] && {
        mkdir -p /var/run/nginx-cache
    }
    [ ! -d /var/run/nginx-cache ] && {
        mkdir -p /var/run/nginx-cache
    }
    # set proper permissions
    chown -R www-data:root /var/lib/nginx/* /var/cache/nginx /var/run/nginx-cache
    # create websites directory
    mkdir -p /var/www/html

    {

        wget -O /var/www/html/index.nginx-debian.html https://raw.githubusercontent.com/VirtuBox/nginx-ee/master/var/www/html/index.nginx-debian.html
        ln -s /etc/nginx/sites-available/default /etc/nginx/sites-enabled/

        [ ! -f /lib/systemd/system/nginx.service ] && {
            wget -O /lib/systemd/system/nginx.service https://raw.githubusercontent.com/VirtuBox/nginx-ee/master/etc/systemd/system/nginx.service
            systemctl enable nginx.service
        }

    } >>/tmp/nginx-ee.log 2>&1

fi

##################################
# Install gcc7 or gcc8 from PPA
##################################
# gcc7 for nginx stable on Ubuntu 16.04 LTS
# gcc8 for nginx mainline on Ubuntu 16.04 LTS & 18.04 LTS

{

    if [ "$DISTRO_VERSION" == "bionic" ] && [ ! -f /etc/apt/sources.list.d/jonathonf-ubuntu-gcc-bionic.list ]; then
        add-apt-repository -y ppa:jonathonf/gcc
        apt-get update
        elif [ "$DISTRO_VERSION" == "xenial" ] && [ ! -f /etc/apt/sources.list.d/jonathonf-ubuntu-gcc-xenial.list ]; then
        add-apt-repository -y ppa:jonathonf/gcc
        apt-get update
    fi
} >>/tmp/nginx-ee.log 2>&1

if [ "$NGINX_RELEASE" == "1" ] && [ "$RTMP" != "y" ]; then
    if [ "$DISTRO_VERSION" == "bionic" ]; then
        if [ ! -x /usr/bin/gcc-8 ]; then
            echo -ne '       Installing gcc-8                       [..]\r'
            {
                apt-get install gcc-8 g++-8 -y
                update-alternatives --remove-all gcc
                update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-8 80 --slave /usr/bin/g++ g++ /usr/bin/g++-8
            } >>/tmp/nginx-ee.log 2>&1
            if [ $? -eq 0 ]; then
                echo -ne "       Installing gcc-8                       [${CGREEN}OK${CEND}]\\r"
                echo -ne '\n'
            else
                echo -e "        Installing gcc-8                      [${CRED}FAIL${CEND}]"
                echo -e '\n      Please look at /tmp/nginx-ee.log\n'
                exit 1
            fi
        fi

        elif [ "$DISTRO_VERSION" == "xenial" ]; then

        if [ ! -x /usr/bin/gcc-8 ]; then
            echo -ne '       Installing gcc-8                       [..]\r'
            {
                apt-get install gcc-8 g++-8 -y  >>/tmp/nginx-ee.log 2>&1

                update-alternatives --remove-all gcc
                update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-8 80 --slave /usr/bin/g++ g++ /usr/bin/g++-8
            } >>/tmp/nginx-ee.log 2>&1
            if [ $? -eq 0 ]; then
                echo -ne "       Installing gcc-8                       [${CGREEN}OK${CEND}]\\r"
                echo -ne '\n'
            else
                echo -e "        Installing gcc-8                      [${CRED}FAIL${CEND}]"
                echo -e '\n      Please look at /tmp/nginx-ee.log\n'
                exit 1
            fi
        fi
    fi
else
    if [ "$DISTRO_VERSION" == "xenial" ]; then
        if [ ! -x /usr/bin/gcc-7 ]; then
            echo -ne '       Installing gcc-7                       [..]\r'

            {
                add-apt-repository -y ppa:jonathonf/gcc-7.1
                apt-get update -y
                apt-get install gcc-7 g++-7 -y
                update-alternatives --remove-all gcc
                update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-7 80 --slave /usr/bin/g++ g++ /usr/bin/g++-7
            } >>/tmp/nginx-ee.log 2>&1
            if [ $? -eq 0 ]; then
                echo -ne "       Installing gcc-7                       [${CGREEN}OK${CEND}]\\r"
                echo -ne '\n'
            else
                echo -e "        Installing gcc-7                      [${CRED}FAIL${CEND}]"
                echo -e '\n      Please look at /tmp/nginx-ee.log\n'
                exit 1
            fi
        fi
    fi
fi

##################################
# Install ffmpeg for rtmp module
##################################

if [ "$RTMP" = "y" ]; then
    echo -ne '       Installing FFMPEG for RTMP module      [..]\r'
    {
        if [ "$DISTRO_VERSION" == "xenial" ]; then
            if [ ! -f /etc/apt/sources.list.d/jonathonf-ubuntu-ffmpeg-4-xenial.list ]; then
                sudo add-apt-repository -y ppa:jonathonf/ffmpeg-4
                sudo apt-get update
                sudo apt-get install ffmpeg -y
            fi
        else
            sudo apt-get install ffmpeg -y
        fi
    } >>/tmp/nginx-ee.log 2>&1
    if [ $? -eq 0 ]; then
        echo -ne "       Installing FFMPEG for RMTP module      [${CGREEN}OK${CEND}]\\r"
        echo -ne '\n'
    else
        echo -e "       Installing FFMPEG for RMTP module      [${CRED}FAIL${CEND}]"
        echo -e '\n      Please look at /tmp/nginx-ee.log\n'
        exit 1
    fi
fi

##################################
# Download additional modules
##################################

# clear previous compilation archives

cd ${DIR_SRC} || exit
rm -rf ${DIR_SRC}/{*.tar.gz,nginx,nginx-1.*,openssl,openssl-*,ngx_brotli,pcre,zlib,incubator-pagespeed-*,build_ngx_pagespeed.sh,install,ngx_http_redis*,ngx_cache_purge}

echo -ne '       Downloading additionals modules        [..]\r'

{
    # cache_purge module
    { [ -d ${DIR_SRC}/ngx_cache_purge ] && {
            git -C ${DIR_SRC}/ngx_cache_purge pull origin master
        }; } || {
        git clone https://github.com/FRiCKLE/ngx_cache_purge.git
    }

    # memcached module
    { [ -d ${DIR_SRC}/memc-nginx-module ] && {
            git -C ${DIR_SRC}/memc-nginx-module pull origin master
        }; } || {
        git clone https://github.com/openresty/memc-nginx-module.git
    }

    # devel kit
    { [ -d ${DIR_SRC}/ngx_devel_kit ] && {
            git -C ${DIR_SRC}/ngx_devel_kit pull origin master
        }; } || {
        git clone https://github.com/simpl/ngx_devel_kit.git
    }
    # headers-more module
    { [ -d ${DIR_SRC}/headers-more-nginx-module ] && {
            git -C ${DIR_SRC}/headers-more-nginx-module pull origin master
        }; } || {
        git clone https://github.com/openresty/headers-more-nginx-module.git
    }
    # echo module
    { [ -d ${DIR_SRC}/echo-nginx-module ] && {
            git -C ${DIR_SRC}/echo-nginx-module pull origin master
        }; } || {
        git clone https://github.com/openresty/echo-nginx-module.git
    }
    # http_substitutions_filter module
    { [ -d ${DIR_SRC}/ngx_http_substitutions_filter_module ] && {
            git -C ${DIR_SRC}/ngx_http_substitutions_filter_module pull origin master
        }; } || {
        git clone https://github.com/yaoweibin/ngx_http_substitutions_filter_module.git
    }
    # redis2 module
    { [ -d ${DIR_SRC}/redis2-nginx-module ] && {
            git -C ${DIR_SRC}/redis2-nginx-module pull origin master
        }; } || {
        git clone https://github.com/openresty/redis2-nginx-module.git
    }
    # srcache module
    { [ -d ${DIR_SRC}/srcache-nginx-module ] && {
            git -C ${DIR_SRC}/srcache-nginx-module pull origin master
        }; } || {
        git clone https://github.com/openresty/srcache-nginx-module.git
    }
    # set-misc module
    { [ -d ${DIR_SRC}/set-misc-nginx-module ] && {
            git -C ${DIR_SRC}/set-misc-nginx-module pull origin master
        }; } || {
        git clone https://github.com/openresty/set-misc-nginx-module.git
    }
    # auth_pam module
    { [ -d ${DIR_SRC}/ngx_http_auth_pam_module ] && {
            git -C ${DIR_SRC}/ngx_http_auth_pam_module pull origin master
        }; } || {
        git clone https://github.com/sto/ngx_http_auth_pam_module.git
    }
    # nginx-vts module
    { [ -d ${DIR_SRC}/nginx-module-vts ] && {
            git -C ${DIR_SRC}/nginx-module-vts pull origin master
        }; } || {
        git clone https://github.com/vozlt/nginx-module-vts.git
    }
    # http redis module
    sudo curl -sL https://people.freebsd.org/~osa/ngx_http_redis-0.3.8.tar.gz | /bin/tar zxf - -C ${DIR_SRC}
    mv ngx_http_redis-0.3.8 ngx_http_redis
    if [ "$RTMP" = "y" ]; then
        { [ -d ${DIR_SRC}/nginx-rtmp-module ] && {
                git -C ${DIR_SRC}/nginx-rtmp-module pull origin master
            }; } || {
            git clone https://github.com/arut/nginx-rtmp-module.git
        }
    fi
    # ipscrub module
    { [ -d ${DIR_SRC}/ipscrubtmp ] && {
            git -C ${DIR_SRC}/ipscrubtmp pull origin master
        }; } || {
        git clone https://github.com/masonicboom/ipscrub.git ipscrubtmp
    }

} >>/tmp/nginx-ee.log 2>&1

if [ $? -eq 0 ]; then
    echo -ne "       Downloading additionals modules        [${CGREEN}OK${CEND}]\\r"
    echo -ne '\n'
else
    echo -e "        Downloading additionals modules      [${CRED}FAIL${CEND}]"
    echo -e '\n      Please look at /tmp/nginx-ee.log\n'
    exit 1
fi

##################################
# Download zlib
##################################

echo -ne '       Downloading zlib                       [..]\r'

{
    cd ${DIR_SRC} || exit 1
    curl -sL http://zlib.net/zlib-1.2.11.tar.gz | /bin/tar zxf - -C ${DIR_SRC}
    mv zlib-1.2.11 zlib

} >>/tmp/nginx-ee.log 2>&1

if [ $? -eq 0 ]; then
    echo -ne "       Downloading zlib                       [${CGREEN}OK${CEND}]\\r"
    echo -ne '\n'
else
    echo -e "       Downloading zlib                       [${CRED}FAIL${CEND}]"
    echo -e '\n      Please look at /tmp/nginx-ee.log\n'
    exit 1
fi

##################################
# Download zlib
##################################

cd ${DIR_SRC} || exit 1

if [ ! -x /usr/bin/pcretest ]; then
    PCRE_VERSION=$(pcretest -C 2>&1 | grep version | awk -F " " '{print $3}')
    if [ "$PCRE_VERSION" != "8.42" ]; then
        echo -ne '       Downloading pcre                       [..]\r'
        {
            curl -sL https://ftp.pcre.org/pub/pcre/pcre-8.42.tar.gz | /bin/tar zxf - -C ${DIR_SRC}
            mv pcre-8.42 pcre

            cd ${DIR_SRC}/pcre || exit 1
            ./configure --prefix=/usr \
            --enable-utf8 \
            --enable-unicode-properties \
            --enable-pcre16 \
            --enable-pcre32 \
            --enable-pcregrep-libz \
            --enable-pcregrep-libbz2 \
            --enable-pcretest-libreadline \
            --enable-jit

            make -j "$(nproc)"
            make install
            mv -v /usr/lib/libpcre.so.* /lib
            ln -sfv ../../lib/"$(readlink /usr/lib/libpcre.so)" /usr/lib/libpcre.so
        } >>/tmp/nginx-ee.log 2>&1
        if [ $? -eq 0 ]; then
            echo -ne "       Downloading pcre                       [${CGREEN}OK${CEND}]\\r"
            echo -ne '\n'
        else
            echo -e "       Downloading pcre                       [${CRED}FAIL${CEND}]"
            echo -e '\n      Please look at /tmp/nginx-ee.log\n'
            exit 1
        fi
    fi
fi

##################################
# Download ngx_broti
##################################

cd ${DIR_SRC} || exit 1

echo -ne '       Downloading brotli                     [..]\r'
{
    git clone https://github.com/eustas/ngx_brotli
    cd ngx_brotli || exit 1
    git submodule update --init --recursive
} >>/tmp/nginx-ee.log 2>&1

if [ $? -eq 0 ]; then
    echo -ne "       Downloading brotli                     [${CGREEN}OK${CEND}]\\r"
    echo -ne '\n'
else
    echo -e "       Downloading brotli      [${CRED}FAIL${CEND}]"
    echo -e '\n      Please look at /tmp/nginx-ee.log\n'
    exit 1
fi

##################################
# Download OpenSSL
##################################

echo -ne '       Downloading openssl                    [..]\r'

cd ${DIR_SRC} || exit 1
{
    git clone https://github.com/openssl/openssl.git
    cd ${DIR_SRC}/openssl || exit 1
} >>/tmp/nginx-ee.log 2>&1

{
    # apply openssl ciphers patch
    curl https://raw.githubusercontent.com/VirtuBox/openssl-patch/master/openssl-equal-3.0.0-dev_ciphers.patch | patch -p1
} >>/tmp/nginx-ee.log 2>&1

if [ $? -eq 0 ]; then
    echo -ne "       Downloading openssl                    [${CGREEN}OK${CEND}]\\r"
    echo -ne '\n'
else
    echo -e "       Downloading openssl      [${CRED}FAIL${CEND}]"
    echo -e '\n      Please look at /tmp/nginx-ee.log\n'
    exit 1
fi

##################################
# Download Naxsi
##################################

cd ${DIR_SRC} || exit 1
if [ "$NAXSI" = "y" ]; then
    echo -ne '       Downloading naxsi                      [..]\r'
    {
        [ -d ${DIR_SRC}/naxsi ] && {
            rm -rf ${DIR_SRC}/naxsi
        }
        curl -sL https://github.com/nbs-system/naxsi/archive/${NAXSI_VER}.tar.gz | /bin/tar zxf - -C ${DIR_SRC}
        mv naxsi-${NAXSI_VER} naxsi
    } >>/tmp/nginx-ee.log 2>&1

    if [ $? -eq 0 ]; then
        echo -ne "       Downloading naxsi                      [${CGREEN}OK${CEND}]\\r"
        echo -ne '\n'
    else
        echo -e "       Downloading naxsi      [${CRED}FAIL${CEND}]"
        echo -e '\n      Please look at /tmp/nginx-ee.log\n'
        exit 1
    fi

fi

##################################
# Download Pagespeed
##################################

cd ${DIR_SRC} || exit 1
if [ "$PAGESPEED" = "y" ]; then
    echo -ne '       Downloading pagespeed                  [..]\r'

    {
        wget -qO build_ngx_pagespeed.sh https://raw.githubusercontent.com/pagespeed/ngx_pagespeed/master/scripts/build_ngx_pagespeed.sh
        chmod +x build_ngx_pagespeed.sh
        if [ "$PAGESPEED_RELEASE" = "1" ]; then
            ./build_ngx_pagespeed.sh --ngx-pagespeed-version latest-beta -b ${DIR_SRC}
        else
            ./build_ngx_pagespeed.sh --ngx-pagespeed-version latest-stable -b ${DIR_SRC}
        fi
    } >>/tmp/nginx-ee.log 2>&1

    if [ $? -eq 0 ]; then
        echo -ne "       Downloading pagespeed                  [${CGREEN}OK${CEND}]\\r"
        echo -ne '\n'
    else
        echo -e "       Downloading pagespeed                  [${CRED}FAIL${CEND}]"
        echo -e '\n      Please look at /tmp/nginx-ee.log\n'
        exit 1
    fi
fi

##################################
# Download Nginx
##################################

cd ${DIR_SRC} || exit 1
echo -ne '       Downloading nginx                      [..]\r'

{
    curl -sL http://nginx.org/download/nginx-${NGINX_VER}.tar.gz | /bin/tar xzf - -C $DIR_SRC
    mv $DIR_SRC/nginx-${NGINX_VER} $DIR_SRC/nginx
} >>/tmp/nginx-ee.log 2>&1

if [ $? -eq 0 ]; then
    echo -ne "       Downloading nginx                      [${CGREEN}OK${CEND}]\\r"
    echo -ne '\n'
else
    echo -e "       Downloading nginx      [${CRED}FAIL${CEND}]"
    echo -e '\n      Please look at /tmp/nginx-ee.log\n'
    exit 1
fi

##################################
# Apply Nginx patches
##################################
cd ${DIR_SRC}/nginx || exit 1
echo -ne '       Applying nginx patches                 [..]\r'

if [ "$NGINX_RELEASE" = "1" ]; then
    {

        curl -s https://raw.githubusercontent.com/nginx-modules/ngx_http_tls_dyn_size/master/nginx__dynamic_tls_records_1.15.5%2B.patch | patch -p1
        curl -s https://raw.githubusercontent.com/centminmod/centminmod/123.09beta01/patches/cloudflare/nginx-1.15.3_http2-hpack.patch | patch -p1
        curl -s https://raw.githubusercontent.com/kn007/patch/master/nginx_auto_using_PRIORITIZE_CHACHA.patch | patch -p1
    } >>/tmp/nginx-ee.log 2>&1

else
    curl -s https://raw.githubusercontent.com/nginx-modules/ngx_http_tls_dyn_size/master/nginx__dynamic_tls_records_1.13.0%2B.patch | patch -p1 >>/tmp/nginx-ee.log 2>&1
fi

if [ $? -eq 0 ]; then
    echo -ne "       Applying nginx patches                 [${CGREEN}OK${CEND}]\\r"
    echo -ne '\n'
else
    echo -e "       Applying nginx patches                 [${CRED}FAIL${CEND}]"
    echo -e '\n      Please look at /tmp/nginx-ee.log\n'
    exit 1
fi

##################################
# Configure Nginx
##################################

echo -ne '       Configuring nginx                      [..]\r'

if [ "$DISTRO_VERSION" = "xenial" ] || [ "$DISTRO_VERSION" = "bionic" ]; then
    if [ "$RTMP" != "y" ]; then
        export CC="/usr/bin/gcc-8"
        export CXX="/usr/bin/gc++-8"
    else
        export CC="/usr/bin/gcc-7"
        export CXX="/usr/bin/gc++-7"
    fi
fi

NGINX_BUILD_OPTIONS="--prefix=/usr/share \
--conf-path=/etc/nginx/nginx.conf \
--http-log-path=/var/log/nginx/access.log \
--error-log-path=/var/log/nginx/error.log \
--lock-path=/var/lock/nginx.lock \
--pid-path=/var/run/nginx.pid \
--http-client-body-temp-path=/var/lib/nginx/body \
--http-fastcgi-temp-path=/var/lib/nginx/fastcgi \
--http-proxy-temp-path=/var/lib/nginx/proxy \
--http-scgi-temp-path=/var/lib/nginx/scgi \
--http-uwsgi-temp-path=/var/lib/nginx/uwsgi \
--modules-path=/usr/share/nginx/modules"

if [ -z "$OVERRIDE_NGINX_MODULES" ]; then
    NGINX_INCLUDED_MODULES="--without-http_uwsgi_module \
    --without-mail_imap_module \
    --without-mail_pop3_module \
    --without-mail_smtp_module \
    --with-http_stub_status_module \
    --with-http_realip_module \
    --with-http_auth_request_module \
    --with-http_addition_module \
    --with-http_geoip_module \
    --with-http_gzip_static_module \
    --with-http_image_filter_module \
    --with-http_mp4_module \
    --with-http_sub_module"

else
    NGINX_INCLUDED_MODULES="$OVERRIDE_NGINX_MODULES"
fi

if [ -z "$OVERRIDE_NGINX_ADDITIONAL_MODULES" ]; then
    NGINX_THIRD_MODULES="--add-module=/usr/local/src/ngx_http_substitutions_filter_module \
    --add-module=/usr/local/src/srcache-nginx-module \
    --add-module=/usr/local/src/ngx_http_redis \
    --add-module=/usr/local/src/redis2-nginx-module \
    --add-module=/usr/local/src/memc-nginx-module \
    --add-module=/usr/local/src/ngx_devel_kit \
    --add-module=/usr/local/src/set-misc-nginx-module \
    --add-module=/usr/local/src/ngx_http_auth_pam_module \
    --add-module=/usr/local/src/nginx-module-vts \
    --add-module=/usr/local/src/ipscrubtmp/ipscrub"
else
    NGINX_THIRD_MODULES="$OVERRIDE_NGINX_ADDITIONAL_MODULES"
fi

./configure \
"${NGINX_CC_OPT[@]}" \
${NGX_NAXSI} \
--with-ld-opt='-Wl,-Bsymbolic-functions -Wl,-z,relro -Wl,-z,now' \
${NGINX_BUILD_OPTIONS} \
--build='VirtuBox Nginx-ee' \
${NGX_USER} \
--with-file-aio \
--with-threads \
--with-http_v2_module \
--with-http_ssl_module \
--with-pcre-jit \
${NGINX_INCLUDED_MODULES} \
${NGINX_THIRD_MODULES} \
${NGX_HPACK} \
${NGX_PAGESPEED} \
${NGX_RTMP} \
--add-module=/usr/local/src/echo-nginx-module \
--add-module=/usr/local/src/headers-more-nginx-module \
--add-module=/usr/local/src/ngx_cache_purge \
--add-module=/usr/local/src/ngx_brotli \
--with-zlib=/usr/local/src/zlib \
--with-openssl=/usr/local/src/openssl \
--with-openssl-opt='enable-tls1_3' \
--sbin-path=/usr/sbin/nginx >>/tmp/nginx-ee.log 2>&1

if [ $? -eq 0 ]; then
    echo -ne "       Configuring nginx                      [${CGREEN}OK${CEND}]\\r"
    echo -ne '\n'
else
    echo -e "        Configuring nginx    [${CRED}FAIL${CEND}]"
    echo -e '\n      Please look at /tmp/nginx-ee.log\n'
    exit 1
fi

##################################
# Compile Nginx
##################################

echo -ne '       Compiling nginx                        [..]\r'

{
    make -j "$(nproc)"
    make install

} >>/tmp/nginx-ee.log 2>&1

if [ $? -eq 0 ]; then
    echo -ne "       Compiling nginx                        [${CGREEN}OK${CEND}]\\r"
    echo -ne '\n'
else
    echo -e "        Compile nginx      [${CRED}FAIL${CEND}]"
    echo -e '\n      Please look at /tmp/nginx-ee.log\n'
    exit 1
fi

##################################
# Perform final tasks
##################################

[ ! -f /etc/apt/preferences.d/nginx-block ] && {
    if [ "$NGINX_PLESK" = "1" ]; then
        {
            # block sw-nginx package updates from APT repository
            echo -e 'Package: sw-nginx*\nPin: release *\nPin-Priority: -1' >/etc/apt/preferences.d/nginx-block
            apt-mark unhold sw-nginx
        } >>/tmp/nginx-ee.log
        elif [ "$NGINX_EASYENGINE" = "1" ]; then
        # replace old TLS v1.3 ciphers suite
        {
            sed -i "s/ssl_ciphers\ \(\"\|'\)\(.*\)\(\"\|'\)/ssl_ciphers \"$TLS13_CIPHERS\"/" /etc/nginx/nginx.conf
            echo -e 'Package: nginx*\nPin: release *\nPin-Priority: -1' >/etc/apt/preferences.d/nginx-block
            apt-mark unhold nginx-ee nginx-common
        } >>/tmp/nginx-ee.log
    else
        {
            echo -e 'Package: nginx*\nPin: release *\nPin-Priority: -1' >/etc/apt/preferences.d/nginx-block
            apt-mark unhold nginx nginx-full nginx-common
        } >>/tmp/nginx-ee.log
    fi
}

{
    systemctl unmask nginx.service
    systemctl enable nginx.service
    systemctl start nginx.service
    rm /etc/nginx/{*.default,*.dpkg-dist}
} >/dev/null 2>&1

echo -ne '       Checking nginx configuration           [..]\r'

# check if nginx -t do not return errors
VERIFY_NGINX_CONFIG=$(nginx -t 2>&1 | grep failed)
if [ -z "$VERIFY_NGINX_CONFIG" ]; then
    {
        systemctl stop nginx
        systemctl start nginx
    } >>/tmp/nginx-ee.log 2>&1
    echo -ne "       Checking nginx configuration           [${CGREEN}OK${CEND}]\\r"
    echo -ne '\n'
else
    echo -e "       Checking nginx configuration           [${CRED}FAIL${CEND}]"
    echo -e '\nPlease look at /tmp/nginx-ee.log or use the command nginx -t to find the issue\n'
fi
# We're done !
echo ""
echo -e "       ${CGREEN}Nginx ee was compiled successfully !${CEND}"
echo -e '\n       Installation log : /tmp/nginx-ee.log\n'
