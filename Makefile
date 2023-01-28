BIN_DIR	= ${HOME}/bin
MAN_DIR	= ${HOME}/man/man1
LIB_DIR	= ${HOME}/lib/Perl

OWNER	= ${USER}
GROUP	= ${USER}

BIN_MODE	= 755
CONFIG_MODE	= 744
MAN_MODE	= 744

prog:
	@echo do a \'make install\' to install update-ddns

install: directories bin libraries manpage

directories:
	@if [ ! -d ${BIN_DIR} ]; then \
		mkdir -p ${BIN_DIR} ; \
	fi 
	@if [ ! -d ${LIB_DIR} ]; then \
		mkdir -p ${LIB_DIR} ; \
	fi
	@if [ ! -d ${MAN_DIR} ]; then \
		mkdir -p ${MAN_DIR} ; \
	fi

bin: update-ddns.plx
	install -p -m ${BIN_MODE} -o ${OWNER} -g ${GROUP} \
		update-ddns.plx ${BIN_DIR}/update-ddns
	install -p -m ${BIN_MODE} -o ${OWNER} -g ${GROUP} \
		test-for-vpn.sh ${BIN_DIR}/test-for-vpn

libraries: lib/zoneedit.pl
	install -p -m ${BIN_MODE} -o ${OWNER} -g ${GROUP} \
		lib/zoneedit.pl ${LIB_DIR}/zoneedit.pl

manpage: man/man1/update-ddns.1
	install -p -m ${MAN_MODE} -o ${OWNER} -g ${GROUP} \
		man/man1/update-ddns.1 ${MAN_DIR}/update-ddns.1
