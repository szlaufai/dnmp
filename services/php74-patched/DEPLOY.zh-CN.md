# PHP 7.4 安全镜像部署

已在 GitHub 的原生 amd64 runner 编译并通过验证：

- 构建：https://github.com/szlaufai/dnmp/actions/runs/39711828072
- 完整镜像：`ghcr.io/szlaufai/dnmp-php74:security-712e60f-c898fb351135980a4ddeaef5ea6cdb8aa5c74fb9`
- 固定摘要：`ghcr.io/szlaufai/dnmp-php74@sha256:2e58af16746d345761accabe537db01cfe1cd6e48116fad6a6195cb2907334db`
- 官方 PHP 补丁提交：`712e60f9edfd03f0960fc4fc3c2c375f42b90aa2`
- 修复：CVE-2026-109618、CVE-2026-109619。

PHP 版本显示为 `7.4.34-dev`，来自官方回移分支的版本定义。它不是 PHP
7.4 恢复维护后的新正式版本。镜像包含现有扩展组合、Composer、Git 和
Supervisor；Imagick 使用 3.7.0，需测试原应用的图像处理行为。

云端已验证扩展加载、FPM 配置、Composer、受控内存耗尽时的立即退出行为，
以及真实 FastCGI 请求。实际网站与数据库、Redis、上传和队列仍需由你验收。

## 在服务器项目目录执行

先确认 `docker compose version`，以下覆盖配置需要 Compose >= 2.24.4。
保留服务器原有的 `docker-compose.yml`、`.env`、业务代码和 Supervisor 配置。
部署会重启 PHP 及其 Supervisor 队列进程，先等待重要任务完成。

```sh
# 获取仅替换 PHP 7.4 镜像的覆盖配置，不需要切换服务器的 Git 分支。
curl -fsSL https://raw.githubusercontent.com/szlaufai/dnmp/c898fb351135980a4ddeaef5ea6cdb8aa5c74fb9/compose.php74-image.yml \
  -o compose.php74-image.yml

export PHP74_IMAGE=ghcr.io/szlaufai/dnmp-php74@sha256:2e58af16746d345761accabe537db01cfe1cd6e48116fad6a6195cb2907334db

# 保留旧镜像，避免更新后无法回滚。
docker image tag "$(docker inspect php --format '{{.Image}}')" dnmp/php74:before-security-update

# 只拉取完整镜像，不在服务器编译。
docker compose -f docker-compose.yml -f compose.php74-image.yml pull php

# 检查新镜像与服务器现有挂载配置是否兼容。
docker compose -f docker-compose.yml -f compose.php74-image.yml run --rm --no-deps --no-build php php-fpm -t
docker compose -f docker-compose.yml -f compose.php74-image.yml run --rm --no-deps --no-build php php -m

# 在测试环境验收业务后，替换线上 PHP 容器。
docker compose -f docker-compose.yml -f compose.php74-image.yml up -d --no-deps --no-build php
docker compose -f docker-compose.yml -f compose.php74-image.yml exec php php -v
docker compose -f docker-compose.yml -f compose.php74-image.yml exec php supervisorctl status

# 更新 Nginx 缓存的 PHP 容器地址，避免容器 IP 改变后出现 502。
docker compose -f docker-compose.yml -f compose.php74-image.yml exec nginx nginx -t
docker compose -f docker-compose.yml -f compose.php74-image.yml exec nginx nginx -s reload
docker compose -f docker-compose.yml -f compose.php74-image.yml logs --tail=100 php
```

若 GHCR 返回未授权，先运行 `docker login ghcr.io -u szlaufai`，密码位置填写
具有 `read:packages` 权限的 GitHub Personal Access Token，随后重试拉取。

验收完成后，将 `PHP74_IMAGE=...` 固定摘要保存到服务器 `.env`，后续维护始终
带上 `-f compose.php74-image.yml`。只运行旧的 Compose 构建配置可能重新生成
未修复的镜像。

## 回滚

```sh
PHP74_IMAGE=dnmp/php74:before-security-update docker compose \
  -f docker-compose.yml -f compose.php74-image.yml up -d --no-deps --no-build php
docker compose -f docker-compose.yml -f compose.php74-image.yml exec nginx nginx -t
docker compose -f docker-compose.yml -f compose.php74-image.yml exec nginx nginx -s reload
```

回滚镜像仍有漏洞，应限制对外访问并继续排查兼容性问题。

如果 Compose 版本过旧：在服务器备份 `docker-compose.yml`，把 `php` 服务的
整个 `build:` 配置删除，改为 `image: ghcr.io/szlaufai/dnmp-php74@sha256:2e58af16746d345761accabe537db01cfe1cd6e48116fad6a6195cb2907334db`，
保留其余配置，再使用不带覆盖文件的 Compose 命令。无需编译。

这个镜像只用于应急修复上述两个 PHP CVE。PHP 7.4 和 Alpine 3.16 都已结束
常规维护，仍需计划迁移到受支持的 PHP 与基础系统。
