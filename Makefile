compile:
	./compile.sh

flash:
	cp ./combined/go60.uf2 ./firmwares/ && chmod u+w ./firmwares/go60.uf2 && ./bin/flash.sh
