mkdir docker
mkdir docker/mysql
mkdir docker/php
mkdir docker/nginx
cat << EOF > docker/mysql/my.cnf
[mysqld]
character-set-server = utf8mb4
collation-server = utf8mb4_general_ci
EOF
cat << EOF > docker/nginx/default.conf
server {
  # port 80 で listen
  # docker-compose.ymlでホストマシン上のポート8000を経由するすべてのリクエスト
  # がコンテナ内のポート80にリダイレクトするように設定済み
  listen 80;
  # ドキュメントルートを設定
  # /var/www/htmlはソースコードを配置しているフォルダ
  root /var/www/html;
  # インデックスファイルを設定
  index index.php;

  location / {
    root /var/www/html;
    index index.php;
    try_files \$uri \$uri/ /index.php?\$query_string;
  }

  location ~ [^/]\.php(/|$) {
    fastcgi_split_path_info ^(.+?\.php)(/.*)$;
    if (!-f \$document_root\$fastcgi_script_name) {
        return 404;
    }
    # https://httpoxy.org/ の脆弱性を緩和する
    fastcgi_param HTTP_PROXY "";
    # TCPソケットを使用してPHP-FPMと通信するための設定
    fastcgi_pass app:9000; 
    # スラッシュで終わるURIの後に追加されるファイル名を設定
    fastcgi_index index.php;
    # fastcgi_paramsファイルに含まれるFastCGIパラメータの設定を読み込む
    include fastcgi_params;
    # SCRIPT_FILENAME パラメータは、PHP-FPM がスクリプト名を決定する際に使用する
    fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
  }
}
EOF
cat << EOF > docker/php/Dockerfile
# イメージを取得
FROM php:8.1.18-fpm
# 独自のphp.iniファイル(PHPの設定ファイル)を 
# コンテナ内の/usr/local/etc/php/ディレクトリにコピー
COPY php.ini /usr/local/etc/php/

# パッケージやPHPの拡張モジュールをインストールするコマンド　を実行
RUN apt-get update && apt-get install -y \
	git \
	curl \
	zip \
	unzip \
    && docker-php-ext-install pdo_mysql

# Composerのインストール
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# 作業ディレクトリを/var/wwwに設定
WORKDIR /var/www
EOF
cat << EOF > docker/php/php.ini
[PHP]
post_max_size = 100M
upload_max_filesize = 100M
variables_order = EGPCS
EOF
mkdir src
cat << EOF > src/index.php
<?php
phpinfo();
EOF
cat << EOF > docker-compose.yml
version: '3'
services:
  nginx:
    image: nginx:1.25.0
    ports:
      - 8000:80
    volumes:
      # ./srcフォルダをコンテナ内の/var/www/htmlにマウント
      - ./src:/var/www/html
      # ./docker/nginxフォルダをコンテナ内の/etc/nginx/conf.dにマウント
      - ./docker/nginx:/etc/nginx/conf.d
    # 依存関係を設定
    depends_on:
      - app
  # PHP-FPMの定義
  app:
    build:
      # Dockerfileを格納するフォルダのパス
      context: ./docker/php
      # Dockerfileのファイル名
      dockerfile: Dockerfile
    # コンテナ内で使用される環境変数を定義(SQLへのアクセス情報)
    environment:
      MYSQL_HOST: \${MYSQL_HOST}
      MYSQL_CHARSET: \${MYSQL_CHARSET}
      MYSQL_ROOT_PASSWORD: \${MYSQL_ROOT_PASSWORD}
      MYSQL_DATABASE: \${MYSQL_DATABASE}
      MYSQL_USER: \${MYSQL_USER}
      MYSQL_PASSWORD: \${MYSQL_PASSWORD}
    volumes:
      # ./srcフォルダをコンテナ内の/var/www/htmlにマウント
     - ./src:/var/www/html   
     # 依存関係を設定(mysqlの起動後に起動する設定)
    depends_on:
      - mysql
    # MySQLの定義
  mysql:
    # MySQL コンテナに使用するイメージを指定
    image: mysql:8.0
    # コンテナ内で使用される環境変数を定義
    environment:
      MYSQL_HOST: \${MYSQL_HOST}
      MYSQL_CHARSET: \${MYSQL_CHARSET}
      MYSQL_ROOT_PASSWORD: \${MYSQL_ROOT_PASSWORD}
      MYSQL_DATABASE: \${MYSQL_DATABASE}
      MYSQL_USER: \${MYSQL_USER}
      MYSQL_PASSWORD: \${MYSQL_PASSWORD}
    volumes:
      # 名前付きボリュームを MySQL コンテナに紐づける
      - mysqldata:/var/lib/mysql
      - ./docker/mysql/my.cnf:/etc/mysql/conf.d/my.cnf
      # - ./docker/mysql/sql:/docker-entrypoint-initdb.d
    ports:
      - 3306:3306
volumes:
  # 名前付きボリュームの作成
  mysqldata:
EOF
cat << EOF > .env
MYSQL_HOST=mysql
MYSQL_ROOT_PASSWORD=rootPass
MYSQL_DATABASE=test-db
MYSQL_USER=testUser
MYSQL_PASSWORD=testPass
MYSQL_CHARSET=utf8mb4
EOF
cat << EOF > READMW.md
[実行ファイル(github)](https://github.com/Merak-h/setup_docker_env/blob/main/setup_docker_php_env.sh)
[解説(Qitta)](https://qiita.com/h_merak/items/2aff7ad451ecbea7f83a)
.envに記載の環境変数は適宜変更してください。
dockerのコンテナを起動するときは\`docker compose up -d \`
dockerのコンテナを削除するときは\`docker compose down \`
EOF
docker compose up -d --build
