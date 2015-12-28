#!/bin/sh

. /etc/sysconfig/heat-params

myip=$(ip addr show eth0 |
       awk '$1 == "inet" {print $2}' | cut -f1 -d/)

CONF_FILE=/etc/systemd/system/swarm-agent.service

cat > $CONF_FILE << EOF
[Unit]
Description=Swarm Agent
After=docker.service
Requires=docker.service
OnFailure=swarm-agent-failure.service

[Service]
TimeoutStartSec=0
ExecStartPre=-/usr/bin/docker kill swarm-agent
ExecStartPre=-/usr/bin/docker rm swarm-agent
ExecStartPre=-/usr/bin/docker pull swarm:$SWARM_VERSION
ExecStart=/usr/bin/docker run -e http_proxy=$HTTP_PROXY \\
                              -e https_proxy=$HTTPS_PROXY \\
                              -e no_proxy=$NO_PROXY \\
                              --name swarm-agent \\
                              swarm:$SWARM_VERSION \\
                              join \\
                              --addr $myip:2375 \\
                              etcd://$ETCD_SERVER_IP:2379/v2/keys/swarm/
ExecStop=/usr/bin/docker stop swarm-agent
ExecStartPost=/usr/local/bin/notify-heat

[Install]
WantedBy=multi-user.target
EOF

chown root:root $CONF_FILE
chmod 644 $CONF_FILE

SCRIPT=/usr/local/bin/notify-heat

cat > $SCRIPT << EOF
#!/bin/sh
until etcdctl --peers $ETCD_SERVER_IP:2379 ls /v2/keys/swarm/docker/swarm/nodes/$myip:2375
do
    echo "Waiting for swarm agent registration..."
    sleep 5
done

curl -sf -X PUT -H 'Content-Type: application/json' \
    --data-binary '{"Status": "SUCCESS", "Reason": "Swarm agent ready", "Data": "OK", "UniqueId": "00000"}' \
    "$AGENT_WAIT_HANDLE"
EOF

chown root:root $SCRIPT
chmod 755 $SCRIPT