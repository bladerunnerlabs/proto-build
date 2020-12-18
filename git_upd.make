T=demo_app_t demo_infra_t
all: $(T)

.PHONY: all $(T)

demo_app_t:
	./git_upd.sh git@github.com:bladerunnerlabs/build_demo_app.git origin master demo_app

demo_infra_t:
	./git_upd.sh git@github.com:bladerunnerlabs/build_demo_infra.git origin master demo_infra



