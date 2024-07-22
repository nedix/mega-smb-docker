setup:
	@docker build . -t mega-smb

up: PORT = 445
up:
	@docker run --rm --name mega-smb \
        --cap-add NET_ADMIN \
        --cap-add SYS_ADMIN \
        --device /dev/fuse \
        -v /sys/fs/cgroup/mega-smb:/sys/fs/cgroup:rw \
        --env-file .env \
        -p $(PORT):445 \
        mega-smb

down:
	-@docker stop mega-smb

shell:
	@docker exec -it mega-smb /bin/sh
