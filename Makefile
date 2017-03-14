# Makefile.

# 8080 stuff

8080: 8080/opbs.lua 8080/opnames.lua 8080/ops.lua
8080/opbs.lua: doc/8080_ops.txt gen/8080_opslen_gen.sh
	gen/8080_opslen_gen.sh > 8080/opbs.lua

8080/opnames.lua: doc/8080_ops.txt gen/8080_names_gen.sh
	gen/8080_names_gen.sh > 8080/opnames.lua

8080/ops.lua: doc/8080_ops.txt gen/8080_ops_gen.lua gen/8080_ops.lua 8080/opnames.lua
	lua gen/8080_ops_gen.lua > 8080/ops.lua

clean:
	rm -f 8080/opbs.lua 8080/opnames.lua 8080/ops.lua
