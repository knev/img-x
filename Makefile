# JDK8 := $(shell /usr/libexec/java_home -v 1.8)
SH=x-exif.sh
BIN=x-exif
OUT= build

.PHONY: nothing install obf repo clean

nothing:
	@echo "usage: make ..."

# obf:
# 	@./version.sh --collect --out $(OUT)
# 	@echo "DONE!"

# repo:
# 	#@git add ...
# 	@git status --untracked-files=no
# 	@echo
# 	@./version.sh --print

install:
	@cp -v ./${SH} ~/bin/${BIN}
	gv --bash ~/bin/${BIN}
	chmod +x ~/bin/${BIN}

# clean:
# 	rm -rf $(OUT) src/se/mitm/version 


