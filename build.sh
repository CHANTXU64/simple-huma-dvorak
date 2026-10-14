node tools/delete_char.js

/bin/rm -r build

mkdir -p build/opencc
mkdir -p build/lua

cp -r opencc/* build/opencc
cp -r lua/* build/lua
cp ./*.yaml build
cp ./*.lua build

# 个人词库 tigress_user.dict.yaml 在 .gitignore 里，不进公开仓库；
# 只有本地存在这个文件时，才在【生成物】里把它加进 import_tables 的最前面：
# librime 对"同词同码"只保留先读到的那条，所以个人词库必须排第一，才能覆盖上游
if [ -f tigress_user.dict.yaml ]; then
  awk '/^  - tigress[ \t]*$/ && !done {print "  - tigress_user"; done=1} {print}' build/tigress.extended.dict.yaml > build/tigress.extended.dict.yaml.tmp
  mv build/tigress.extended.dict.yaml.tmp build/tigress.extended.dict.yaml
fi

/bin/rm build/orig.tigress.dict.yaml
/bin/rm build/orig.tigress_ci.dict.yaml
/bin/rm build/orig.tigress_simp_ci.dict.yaml
/bin/rm build/opencc/orig.hu_cf.txt
/bin/rm ./tigress.dict.yaml
/bin/rm ./tigress_ci.dict.yaml
/bin/rm ./tigress_simp_ci.dict.yaml
/bin/rm opencc/hu_cf.txt

