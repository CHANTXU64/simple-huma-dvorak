node tools/delete_char.js

/bin/rm -r build

mkdir -p build/opencc
mkdir -p build/lua

cp -r opencc/* build/opencc
cp -r lua/* build/lua
cp ./*.yaml build
cp ./*.lua build

/bin/rm build/orig.tiger.dict.yaml
/bin/rm build/orig.tigress.dict.yaml
/bin/rm build/orig.tigress_ci.dict.yaml
/bin/rm build/orig.tigress_simp_ci.dict.yaml
/bin/rm build/orig.stroke.dict.yaml
/bin/rm build/opencc/orig.hu_cf.txt
/bin/rm ./tiger.dict.yaml
/bin/rm ./tigress.dict.yaml
/bin/rm ./tigress_ci.dict.yaml
/bin/rm ./tigress_simp_ci.dict.yaml
/bin/rm ./stroke.dict.yaml
/bin/rm opencc/hu_cf.txt

