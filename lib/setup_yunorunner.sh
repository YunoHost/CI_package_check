#!/bin/bash

# User which execute the CI software.
ci_user=yunorunner
# Web path of the CI
ci_path=ci

echo_bold "> Installation of YunoRunner..."
yunohost app install --force https://github.com/YunoHost-Apps/yunorunner_ynh_core -a "domain=$domain&path=/$ci_path"

# Stop YunoRunner
systemctl stop yunorunner

# Remove the original database, in order to rebuilt it with the new config.
rm /var/www/yunorunner/db.sqlite

# Create a random token for ciclic
cat /dev/urandom | tr -dc _A-Za-z0-9 | head -c${1:-80} | tee /var/www/yunorunner/token /var/www/yunorunner/tokens

# Reboot YunoRunner to consider the configuration
echo_bold "> Reboot YunoRunner..."
systemctl daemon-reload

# Put YunoRunner as the default app on the root of the domain
yunohost app makedefault -d "$domain" yunorunner

# Add an access to badges in the nginx config
sed -i "s@^}$@\n\tlocation /$ci_path/badges/ {\n\t\talias /home/CI_package_check/badges/;\n\t\tautoindex on;\n\t}\n}@" /etc/nginx/conf.d/$domain.d/yunorunner.conf
systemctl reload nginx
