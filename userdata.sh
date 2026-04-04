#!/bin/bash
exec > /tmp/setup.log 2>&1

echo "===== Setup started at $(date) ====="

# ── SYSTEM UPDATE ─────────────────────────────────────────────
apt-get update -y
apt-get upgrade -y

# ── INSTALL DEPENDENCIES ──────────────────────────────────────
apt-get install -y ca-certificates curl gnupg unzip git mysql-client

# ── INSTALL DOCKER (official repo - works on Ubuntu 22 & 24) ──
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) \
  signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io

systemctl start docker
systemctl enable docker
usermod -aG docker ubuntu
echo "Docker installed: $(docker --version)"

# ── INSTALL AWS CLI ───────────────────────────────────────────
curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" \
  -o "/tmp/awscliv2.zip"
unzip -q /tmp/awscliv2.zip -d /tmp
/tmp/aws/install
echo "AWS CLI installed: $(aws --version)"

# ── INSTALL CLOUDWATCH AGENT ──────────────────────────────────
curl -s https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb \
  -o /tmp/amazon-cloudwatch-agent.deb
dpkg -i /tmp/amazon-cloudwatch-agent.deb
echo "CloudWatch agent installed"

# ── WAIT FOR IAM ROLE TO BE READY ────────────────────────────
echo "Waiting for IAM role..."
sleep 30

# ── FETCH CREDENTIALS FROM SSM ───────────────────────────────
REGION="ap-south-1"
PROJECT="demo-app"

echo "Fetching SSM parameters..."

DB_HOST=$(aws ssm get-parameter \
  --name "/${PROJECT}/db/host" \
  --region $REGION \
  --query "Parameter.Value" \
  --output text 2>>/tmp/setup.log)

DB_NAME=$(aws ssm get-parameter \
  --name "/${PROJECT}/db/name" \
  --region $REGION \
  --query "Parameter.Value" \
  --output text 2>>/tmp/setup.log)

DB_USER=$(aws ssm get-parameter \
  --name "/${PROJECT}/db/username" \
  --with-decryption \
  --region $REGION \
  --query "Parameter.Value" \
  --output text 2>>/tmp/setup.log)

DB_PASS=$(aws ssm get-parameter \
  --name "/${PROJECT}/db/password" \
  --with-decryption \
  --region $REGION \
  --query "Parameter.Value" \
  --output text 2>>/tmp/setup.log)

echo "DB_HOST=$DB_HOST"
echo "DB_NAME=$DB_NAME"
echo "DB_USER=$DB_USER"
echo "SSM fetch complete"

# ── CREATE APP ────────────────────────────────────────────────
mkdir -p /app
cd /app

cat <<'PKGEOF' > package.json
{
  "name": "aws-terraform-app",
  "version": "1.0.0",
  "main": "app.js",
  "dependencies": {
    "mysql2": "^3.6.0"
  }
}
PKGEOF

cat <<'APPEOF' > app.js
const http = require('http');
const mysql = require('mysql2');
const os = require('os');

const pool = mysql.createPool({
  host: process.env.DB_HOST,
  user: process.env.DB_USER,
  password: process.env.DB_PASS,
  database: process.env.DB_NAME,
  waitForConnections: true,
  connectionLimit: 10,
  connectTimeout: 30000,
});

pool.execute(`
  CREATE TABLE IF NOT EXISTS visits (
    id INT AUTO_INCREMENT PRIMARY KEY,
    ip_address VARCHAR(50),
    visited_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
  )
`, (err) => {
  if (err) console.error('Table error:', err.message);
  else console.log('Visits table ready');
});

const server = http.createServer((req, res) => {
  if (req.url === '/favicon.ico') { res.writeHead(204); res.end(); return; }
  const clientIp = req.headers['x-forwarded-for'] || req.socket.remoteAddress;
  pool.execute('INSERT INTO visits (ip_address) VALUES (?)', [clientIp], () => {});
  pool.execute('SELECT COUNT(*) as total FROM visits', (err, rows) => {
    const count = err ? 'DB Error: ' + err.message : rows[0].total;
    res.writeHead(200, { 'Content-Type': 'text/html' });
    res.end(`
      <html>
        <head><title>Sudha AWS App</title></head>
        <body style="font-family:Arial;text-align:center;padding:50px;background:#f0f8ff">
          <h1>Deployed with Terraform on AWS!</h1>
          <h2>Cloud & DevOps Project by Sudha Hiremath</h2>
          <hr/>
          <h3>Total Visits: ${count}</h3>
          <p>Server: ${os.hostname()} | Time: ${new Date().toISOString()}</p>
          <p>Stack: EC2 + RDS MySQL + S3 + CloudWatch + Terraform + Docker</p>
        </body>
      </html>
    `);
  });
});

server.listen(3000, () => console.log('App running on port 3000, DB: ' + process.env.DB_HOST));
APPEOF

cat <<'DEOF' > Dockerfile
FROM node:18-alpine
WORKDIR /app
COPY package.json .
RUN npm install
COPY app.js .
EXPOSE 3000
CMD ["node", "app.js"]
DEOF

# ── BUILD AND RUN DOCKER ──────────────────────────────────────
echo "Building Docker image..."
docker build -t myapp .
echo "Docker build done"

docker run -d \
  --name myapp \
  --restart always \
  -p 80:3000 \
  -e DB_HOST="$DB_HOST" \
  -e DB_USER="$DB_USER" \
  -e DB_PASS="$DB_PASS" \
  -e DB_NAME="$DB_NAME" \
  myapp

echo "Docker container started: $(docker ps --format '{{.Names}} {{.Status}}')"

# ── CONFIGURE CLOUDWATCH ──────────────────────────────────────
cat <<'CWEOF' > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/tmp/setup.log",
            "log_group_name": "/ec2/sudha-freetier/setup",
            "log_stream_name": "{instance_id}"
          }
        ]
      }
    }
  },
  "metrics": {
    "metrics_collected": {
      "mem": { "measurement": ["mem_used_percent"] },
      "disk": { "measurement": ["disk_used_percent"] }
    }
  }
}
CWEOF

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
  -s

echo "CloudWatch agent started"

# ── DONE ──────────────────────────────────────────────────────
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
echo "===== Setup complete at $(date) ====="
echo "App URL: http://$PUBLIC_IP"
echo "Docker: $(docker ps --format '{{.Names}} - {{.Status}}')"
touch /tmp/setup-done.txt