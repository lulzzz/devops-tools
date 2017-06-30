hostname
uname -a

wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo apt-key add -
echo "deb https://artifacts.elastic.co/packages/5.x/apt stable main" | sudo tee -a /etc/apt/sources.list.d/elastic-5.x.list

uniq /etc/apt/sources.list.d/elastic-5.x.list > tmp
sudo mv -f tmp /etc/apt/sources.list.d/elastic-5.x.list
sudo chmod 644 /etc/apt/sources.list.d/elastic-5.x.list

sudo apt-get update && sudo apt-get install metricbeat
sudo update-rc.d metricbeat defaults 95 10
sudo systemctl enable metricbeat.service

sudo cp /etc/metricbeat/metricbeat.yml /etc/metricbeat/metricbeat.bak.yml

hostname=$(hostname)
environmentname=elastic5.%metricenvironment%

sudo sed -i 's/^    #- diskio$/    - diskio/g' /etc/metricbeat/metricbeat.yml
sudo sed -i 's/^#name:$/name: '"$environmentname"'.'"$hostname"'/g' /etc/metricbeat/metricbeat.yml
sudo sed -i 's/^#fields:$/fields:/g' /etc/metricbeat/metricbeat.yml
sudo sed -i 's/^#  env: staging$/  env: '"$environmentname"'/g' /etc/metricbeat/metricbeat.yml
sudo sed -i 's,^  hosts: \["localhost:9200"\]$,  hosts: \["%metricserver%"\],g' /etc/metricbeat/metricbeat.yml
sudo sed -i 's/^  #username: "elastic"$/  username: "%metricusername%"/g' /etc/metricbeat/metricbeat.yml
sudo sed -i 's/^  #password: "changeme"$/  password: "%metricpassword%"/g' /etc/metricbeat/metricbeat.yml

sudo diff /etc/metricbeat/metricbeat.bak.yml /etc/metricbeat/metricbeat.yml || true

sudo systemctl start metricbeat.service