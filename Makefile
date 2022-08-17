BIN_DIR	= ${HOME}/bin
MAN_DIR	= ${HOME}/man/man1
LIB_DIR	= ${HOME}/lib/Perl
CFG_DIR	= ${HOME}/.config/update-ddns

CFG_FILE	= update-ddns.conf

OWNER	= ${USER}
GROUP	= ${USER}

BIN_MODE	= 755
CONFIG_MODE	= 744
MAN_MODE	= 744

prog:
	@echo do a \'make install\' to install update-ddns

install: directories bin libraries manpage config

directories:
	@if [ ! -d ${BIN_DIR} ]; then \
		mkdir -p ${BIN_DIR} ; \
	fi 
	@if [ ! -d ${CFG_DIR} ]; then \
		mkdir -p ${CFG_DIR} ; \
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

libraries: lib/zoneedit.pl
	install -p -m ${BIN_MODE} -o ${OWNER} -g ${GROUP} \
		lib/zoneedit.pl ${LIB_DIR}/zoneedit.pl

manpage: man/man1/update-ddns.1
	install -p -m ${MAN_MODE} -o ${OWNER} -g ${GROUP} \
		man/man1/update-ddns.1 ${MAN_DIR}/update-ddns.1

config: update-ddns.conf
	@if [ ! -f ${CFG_DIR}/${CFG_FILE} ]; then \
		echo installing ${CFG_FILE} into ${CFG_DIR}/${CFG_FILE} ; \
		install -p -m ${CONFIG_MODE} -o ${OWNER} -g ${GROUP} \
			update-ddns.conf ${CFG_DIR}/${CFG_FILE} ; \
	else \
		echo The config file here is meant as your initial version only ; \
		echo ${CFG_DIR}/${CFG_FILE} file already exists - NOT over-writing ; \
		echo make your changes directly to ${CFG_DIR}/${CFG_FILE} ; \
	fi
