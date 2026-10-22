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

## Production：直接替换原 PHP 服务

staging 已通过此方式部署。Production 使用同一个固定镜像摘要，直接修改原
PHP 7.4 服务，保留容器名称、端口、目录挂载、启动命令和网络配置。
不使用 `compose.php74-image.yml`，也不新增名为 `php` 的服务。

以下命令在 production 的项目目录、同一个 SSH 终端内按顺序执行。
部署会重启 PHP 及其 Supervisor 队列进程，先等待重要任务完成。

### 1. 确认服务名并备份

```sh
cd /var/www/dnmp
PHP_SERVICE=$(sudo docker inspect php --format '{{index .Config.Labels "com.docker.compose.service"}}')
printf '原 PHP 服务名：%s\n' "$PHP_SERVICE"
# 预期为 php74；如果为空或与文件不符，先确认正确的 Compose 文件。

test -n "$PHP_SERVICE" || exit 1
STAMP=$(date +%Y%m%d-%H%M%S)
sudo cp -a docker-compose.yml "docker-compose.yml.backup-$STAMP"
BACKUP_IMAGE="dnmp/php74:backup-$STAMP"
sudo docker image tag "$(sudo docker inspect php --format '{{.Image}}')" "$BACKUP_IMAGE"
printf '配置备份：docker-compose.yml.backup-%s\n旧镜像：%s\n' "$STAMP" "$BACKUP_IMAGE"
```

记录输出的备份文件和镜像标签。如果重新连接 SSH，回滚时需要重新设置
`STAMP` 和 `BACKUP_IMAGE`，或直接使用记录下来的值。

### 2. 修改原服务

编辑 production 原有的 `docker-compose.yml`：找到上一步确认的服务
（以下以 `php74` 为例），删除整个 `build:` 配置及它的子项，添加固定镜像：

```yaml
services:
  php74:
    image: ghcr.io/szlaufai/dnmp-php74@sha256:2e58af16746d345761accabe537db01cfe1cd6e48116fad6a6195cb2907334db
    platform: linux/amd64
    container_name: php
    # 原有 ports、volumes、command、environment、networks 等全部保留
```

不要照这个片段覆盖整个服务，否则会丢失原有挂载和端口。特别是宿主机
Nginx 使用 `fastcgi_pass 127.0.0.1:9000` 时，必须保留原有 9000 端口映射。
Nginx 配置保持不变。若原有 image 字段已经存在，直接替换，避免重复字段。

### 3. 拉取与检查，不编译

```sh
sudo docker compose -f docker-compose.yml config --quiet
sudo docker compose -f docker-compose.yml pull "$PHP_SERVICE"
sudo docker compose -f docker-compose.yml run --rm --no-deps "$PHP_SERVICE" php-fpm -t
sudo docker compose -f docker-compose.yml run --rm --no-deps "$PHP_SERVICE" php -v
sudo docker compose -f docker-compose.yml run --rm --no-deps "$PHP_SERVICE" php -m
```

FPM 应提示配置检查成功，PHP 应显示 `7.4.34-dev`。检查不通过时先排查，
不要继续替换生产容器。`run` 不支持 `--no-build`；原服务的 `build` 已删除，
因此这里不会编译，也不会启动 Supervisor 队列。

若 GHCR 提示未授权，先执行 `sudo docker login ghcr.io -u szlaufai`，密码处
填写具有 `read:packages` 权限的 GitHub Personal Access Token，再重试拉取。

### 4. 替换原容器

```sh
sudo docker compose -f docker-compose.yml up -d --no-deps --no-build --force-recreate "$PHP_SERVICE"
```

此操作会替换原服务并继续使用 `container_name: php`。它不重启其他 Compose
服务，也不编译源码。不要手动删除旧容器或先运行 `down`。

### 5. 验证

```sh
sudo docker compose -f docker-compose.yml ps "$PHP_SERVICE"
sudo docker inspect php --format 'image={{.Config.Image}}'
sudo docker exec php php -v
sudo docker exec php cat /usr/local/share/php-security/source-commit
sudo docker exec php supervisorctl status
sudo docker logs --tail=100 php
```

预期镜像为上述固定摘要，版本为 `7.4.34-dev`，补丁标记为
`712e60f9edfd03f0960fc4fc3c2c375f42b90aa2`，应运行的队列进程状态为 RUNNING。
再检查实际网站、登录、数据库/Redis、上传、图像处理和队列业务。
宿主机 Nginx 使用原有 `127.0.0.1:9000` 映射时，不需要更改或重载 Nginx。

后续维护直接使用原来的 `docker-compose.yml`。不要附加
`compose.php74-image.yml`，也不需要使用 `PHP74_IMAGE` 环境变量。

## 回滚

在相同 SSH 终端中执行；如果换了终端，先使用步骤 1 记录的实际值设置变量。

```sh
sudo cp -a "docker-compose.yml.backup-$STAMP" docker-compose.yml
# 备份配置中的原 build 仍可用；显式指定本地备份镜像以避免重新编译。
cat > /tmp/dnmp-php74-rollback.yml <<EOF
services:
  ${PHP_SERVICE}:
    image: ${BACKUP_IMAGE}
    pull_policy: never
EOF
sudo docker compose -f docker-compose.yml -f /tmp/dnmp-php74-rollback.yml \
  up -d --no-deps --no-build --force-recreate "$PHP_SERVICE"
sudo docker exec php php -v
```

回滚配置仅覆盖同一个原服务的镜像，不新增服务。旧镜像仍有漏洞，应限制
对外访问并继续排查兼容性问题。保留备份镜像，确认稳定前不要执行 image prune。

这个镜像只用于应急修复上述两个 PHP CVE。PHP 7.4 和 Alpine 3.16 都已结束
常规维护，仍需计划迁移到受支持的 PHP 与基础系统。
