#!/bin/bash -ex
selfsum="$(openssl dgst -sha256 "$0")"
isunum="$(ip r get 1.1.1.1|grep -o 'src 192.168.0.1\(.\)'|cut -d. -f 4|cut -c 2)"
export PATH=/home/isucon/ruby/bin:$PATH
#
cd ~/git/
git pull --rebase
if [ "_${selfsum}" != "_$(openssl dgst -sha256 "$0")" ]; then
  exec $0
fi

(
  cd ~/git/webapp/ruby
  #bundle exec stackprof --d3-flamegraph app.rb /run/isuports/stackprof/* > ~isucon/public_html/stackprof.html
) || :
#(
#  cd ~/git/webapp/go
#  go build -v -o isuconquest .
#) || :

cat env.all.sh env.${isunum}.sh > ~/env.sh
sudo cp -r ~/git/systemd/system/* /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl restart isupipe-ruby.service

sudo cp ~/git/nginx.conf /etc/nginx/nginx.conf
sudo nginx -t
sudo nginx -s reload || :


# (
#   cd ~/git/webapp/ruby
#   source ~/env.secret.sh
#   source ~/git/env.sh
#   export RACK_ENV=production
#   export NEWRELIC_LICENSE_KEY
#   bundle exec newrelic deployment -r "$(git rev-parse HEAD)"
# ) || :

sudo bash -c 'cp /var/log/nginx/access.log /var/log/nginx/access.log.$(date +%s) && echo > /var/log/nginx/access.log; echo > /tmp/isu-query.log; echo > /tmp/isu-rack.log; echo > /tmp/isu.systemd.log; echo > /tmp/isu-params.log; test -d /tmp/stackprof && rm -f /tmp/stackprof/*; if [[ -e /var/lib/mysql/mysql-slow.log ]]; then echo > /var/lib/mysql/mysql-slow.log; fi; touch /tmp/isu0.log; chown isucon:isucon /tmp/isu*.log'
