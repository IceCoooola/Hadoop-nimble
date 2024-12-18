# Setup guide for Nimble Integration

### Installation
Install Java and Apache Maven:
```bash
sudo apt update
sudo apt install default-jdk maven
```

Install LXC containers:
```bash
sudo snap install lxd # config is in /var/snap/lxd/common
sudo usermod -a -G lxd <username> # then re-login
sudo lxd init
```

To resolve DNS from host (optional):
```bash
lxc network get lxdbr0 ipv4.address # for DNS address; ex. 10.88.138.1/24

sudo resolvectl dns lxdbr0 <address_from_above>  # remove the subset: /24
sudo resolvectl domain lxdbr0 '~lxd'
```

### Compilation
We want to compile the entire Hadoop distribution and deploy it inside containers.

```bash
# cd <repo-top-level>
mvn package -Pdist -DskipTests -Dtar -Dmaven.javadoc.skip=true
```

Configuration options for tweaking Nimble are below.
These can be set via the `core-site.xml` config file.

fs.nimbleURI
: URL of NimbleLedger's REST endpoint.

fs.nimble.batchSize
: Number of operations to batch before incrementing the counter.

fs.nimble.service.id
: Identity of NimbleLedger based on "/serviceid". It is base64url encoded.

fs.nimble.service.publicKey
: Public Key of NimbleLedger based on "/serviceid". It is base64url encoded.

fs.nimble.service.handle
: Handle to use for TMCS reported when formatting the HDFS file system. It is base64url encoded.
After formatting the file system, look for a message like the following:
    ```
    2022-10-28 02:27:17,586 INFO nimble.TMCS: Formatted TMCS: NimbleServiceID{identity=C9JtOpmXyBd-anyeBbhr5RZ0ac2urm5Nt-z_C88wfvU, publicKey=A8ABjZekZrccR7eq7ASkDNt0689wd3klvWUW6wIzYmJz, handle=yfQi-y8v4k1GIfgjaKon7w, signPublicKey=MFYwEAYHKoZIzj0CAQYFK4EEAAoDQgAEXNoPgT2QAqTPaTJk0wowGyl4fQx7UywYJoqaR8UyARHgJGld6QOaH3mv1OQYIKwZNb3fBr7gPMM7LypIWbNNbQ, signPrivateKey=MD4CAQAwEAYHKoZIzj0CAQYFK4EEAAoEJzAlAgEBBCBzv_4v64jTXxngYxfDnFQAG-3M8rhc5heXrB9sSnGcmw}
    ```

### Setup Local cluster

```bash
# Setup java
sudo apt update
sudo apt install -y bash-completion default-jre

# Setup environment variables (for bash)
export JAVA_HOME=/usr/lib/jvm/default-java
export PATH=/opt/hadoop-3.3.3/bin:$PATH

# (for fish)
set -x JAVA_HOME /usr/lib/jvm/default-java
set -x PATH /opt/hadoop-3.3.3/bin $PATH
```

Copy Hadoop installation:

```bash
sudo cp -ar ./hadoop-dist/target/hadoop-3.3.3 /opt/hadoop-3.3.3

# Replace localhost with IP address. Then you can access hdfs namenode webUI from ip:9870.
echo "\
<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<?xml-stylesheet type=\"text/xsl\" href=\"configuration.xsl\"?>
<configuration>
	<property>
		<name>fs.defaultFS</name>
		<value>hdfs://localhost:9000</value>
	</property>
	<property>
		<name>fs.nimbleURI</name>
		<value>http://localhost:8082/</value>
	</property>
	<property>
		<name>fs.nimble.batchSize</name>
		<value>2</value>
	</property>
</configuration>
" >/opt/hadoop-3.3.3/etc/hadoop/core-site.xml
```

Start Hadoop:
```bash
# Format namenode
hdfs namenode -format

# Start
hdfs --daemon start namenode
hdfs --daemon start datanode

# Logs are inside /opt/hadoop-3.3.3/logs
```

Recompiling specific parts:
```bash
# hadoop-hdfs-client
cp hadoop-hdfs-project/hadoop-hdfs-native-client/target/hadoop-hdfs-native-client-3.3.3.jar /opt/hadoop-3.3.3/share/hadoop/hdfs/hadoop-hdfs-client-3.3.3.jar
```

### Setup Containers

```bash
lxc launch images:ubuntu/20.04 namenode
lxc launch images:ubuntu/20.04 datanode

lxc exec namenode -- apt update
lxc exec namenode -- apt install -y bash-completion default-jre
lxc exec datanode -- apt update
lxc exec datanode -- apt install -y bash-completion default-jre
```

Deploy entire hadoop distribution inside containers:
```bash
# cd <repo-top-level>
lxc file push ./hadoop-dist/target/hadoop-3.3.3.tar.gz namenode/opt/hadoop-3.3.3.tar.gz
lxc file push ./hadoop-dist/target/hadoop-3.3.3.tar.gz datanode/opt/hadoop-3.3.3.tar.gz
lxc exec namenode -- mv /opt/hadoop-3.3.3 /opt/hadoop-3.3.3.bak
lxc exec datanode -- mv /opt/hadoop-3.3.3 /opt/hadoop-3.3.3.bak
lxc exec namenode -- tar -xzf /opt/hadoop-3.3.3.tar.gz -C /opt
lxc exec datanode -- tar -xzf /opt/hadoop-3.3.3.tar.gz -C /opt

# Deploy Hadoop config
echo "\
<configuration>
	<property>
		<name>fs.defaultFS</name>
		<value>hdfs://namenode.lxd:9000</value>
	</property>
	<property>
		<name>fs.nimbleURI</name>
		<value>http://localhost:8082/</value>
	</property>
	<property>
		<name>fs.nimble.batchSize</name>
		<value>2</value>
	</property>
	<property>
		<name>dfs.namenode.fs-limits.min-block-size</name>
		<value>1</value>
	</property>
</configuration>
" >/tmp/core-site.xml

lxc file push /tmp/core-site.xml namenode/opt/hadoop-3.3.3/etc/hadoop/core-site.xml
lxc file push /tmp/core-site.xml datanode/opt/hadoop-3.3.3/etc/hadoop/core-site.xml

# Setup environment variable (for root user)
lxc exec namenode -- bash -c "echo 'export JAVA_HOME=/usr/lib/jvm/default-java' >>/root/.bashrc"
lxc exec namenode -- bash -c "echo 'export PATH=/opt/hadoop-3.3.3/bin:\$PATH' >>/root/.bashrc"
lxc exec datanode -- bash -c "echo 'export JAVA_HOME=/usr/lib/jvm/default-java' >>/root/.bashrc"
lxc exec datanode -- bash -c "echo 'export PATH=/opt/hadoop-3.3.3/bin:\$PATH' >>/root/.bashrc"
```

Start Hadoop:
```bash
# Format namenode
lxc exec namenode --env JAVA_HOME=/usr/lib/jvm/default-java -- /opt/hadoop-3.3.3/bin/hdfs namenode -format

# Start
lxc exec namenode --env JAVA_HOME=/usr/lib/jvm/default-java -T -- /opt/hadoop-3.3.3/bin/hdfs --daemon start namenode
lxc exec datanode --env JAVA_HOME=/usr/lib/jvm/default-java -T -- /opt/hadoop-3.3.3/bin/hdfs --daemon start datanode
```

Enable debug logging:
```bash
$ lxc exec namenode -- vim /opt/hadoop-3.3.3/etc/hadoop/log4j.properties
# Add the following line & restart NN/DN
log4j.logger.org.apache.hadoop.hdfs.server.nimble.NimbleUtils=DEBUG
```

### Others
View logs:
```bash
# Namenode
lxc exec namenode -- tail -f /opt/hadoop-3.3.3/logs/hadoop-root-namenode-namenode.log

# Datanode
lxc exec datanode -- tail -f /opt/hadoop-3.3.3/logs/hadoop-root-datanode-datanode.log
```

Interactive shell:
```bash
lxc exec namenode -- bash
```

Testing Nimble:
```bash
# From host
java -cp 'hadoop-hdfs-project/hadoop-hdfs/target/hadoop-hdfs-3.3.3.jar:hadoop-dist/target/hadoop-3.3.3/etc/hadoop:hadoop-dist/target/hadoop-3.3.3/share/hadoop/common/lib/*:hadoop-dist/target/hadoop-3.3.3/share/hadoop/common/*:hadoop-dist/target/hadoop-3.3.3/share/hadoop/hdfs/lib/*:hadoop-dist/target/hadoop-3.3.3/share/hadoop/hdfs/*' org.apache.hadoop.hdfs.server.nimble.NimbleTester

# From container
export CLASSPATH=/opt/hadoop-3.3.3/etc/hadoop:/opt/hadoop-3.3.3/share/hadoop/common/lib/*:/opt/hadoop-3.3.3/share/hadoop/common/*:/opt/hadoop-3.3.3/share/hadoop/hdfs:/opt/hadoop-3.3.3/share/hadoop/hdfs/lib/*:/opt/hadoop-3.3.3/share/hadoop/hdfs/*:/opt/hadoop-3.3.3/share/hadoop/mapreduce/*:/opt/hadoop-3.3.3/share/hadoop/yarn/lib/*:/opt/hadoop-3.3.3/share/hadoop/yarn/*
java -cp hadoop-hdfs-3.3.3.jar:$CLASSPATH org.apache.hadoop.hdfs.server.nimble.NimbleTester
```

Compile and run Nimble only (for development):
```bash
# In host
mkdir tmp/
javac -d tmp/ -cp 'hadoop-hdfs-project/hadoop-hdfs/target/hadoop-hdfs-3.3.3.jar:hadoop-dist/target/hadoop-3.3.3/etc/hadoop:hadoop-dist/target/hadoop-3.3.3/share/hadoop/common/lib/*:hadoop-dist/target/hadoop-3.3.3/share/hadoop/common/*:hadoop-dist/target/hadoop-3.3.3/share/hadoop/hdfs/lib/*:hadoop-dist/target/hadoop-3.3.3/share/hadoop/hdfs/*' \
  hadoop-hdfs-project/hadoop-hdfs/src/main/java/org/apache/hadoop/hdfs/Nimble.java
java -cp 'tmp/:hadoop-hdfs-project/hadoop-hdfs/target/hadoop-hdfs-3.3.3.jar:hadoop-dist/target/hadoop-3.3.3/etc/hadoop:hadoop-dist/target/hadoop-3.3.3/share/hadoop/common/lib/*:hadoop-dist/target/hadoop-3.3.3/share/hadoop/common/*:hadoop-dist/target/hadoop-3.3.3/share/hadoop/hdfs/lib/*:hadoop-dist/target/hadoop-3.3.3/share/hadoop/hdfs/*' org.apache.hadoop.hdfs.server.nimble.NimbleTester

# In container (after doing above)
lxc file push -r tmp/org namenode/root/
lxc exec namenode -- bash
export CLASSPATH=/root:/opt/hadoop-3.3.3/etc/hadoop:/opt/hadoop-3.3.3/share/hadoop/common/lib/*:/opt/hadoop-3.3.3/share/hadoop/common/*:/opt/hadoop-3.3.3/share/hadoop/hdfs:/opt/hadoop-3.3.3/share/hadoop/hdfs/lib/*:/opt/hadoop-3.3.3/share/hadoop/hdfs/*:/opt/hadoop-3.3.3/share/hadoop/mapreduce/*:/opt/hadoop-3.3.3/share/hadoop/yarn/lib/*:/opt/hadoop-3.3.3/share/hadoop/yarn/*
java org/apache/hadoop/hdfs/Nimble
```

WebHDFS Commands:

```bash
# Set the user for running commands
USER=root

# Change perms
curl -i -X PUT "http://namenode.lxd:9870/webhdfs/v1/?op=SETPERMISSION&permission=777&user.name=$USER"

# CREATE file (single block)
curl -i -X PUT -T /opt/hadoop-3.3.3/README.txt "http://datanode.lxd:9864/webhdfs/v1/foo?op=CREATE&user.name=$USER&namenoderpcaddress=localhost:9000&createflag=&createparent=true&overwrite=false&permission=777"

# CREATE file (multi block)
curl -i -X PUT -T /opt/hadoop-3.3.3/share/hadoop/yarn/hadoop-yarn-applications-catalog-webapp-3.3.3.war "http://datanode.lxd:9864/webhdfs/v1/yarn.war?op=CREATE&user.name=$USER&namenoderpcaddress=localhost:9000&createflag=&createparent=true&overwrite=false&permission=777"

# APPEND file
curl -i -X POST -T /opt/hadoop-3.3.3/README.txt "http://datanode.lxd:9864/webhdfs/v1/foo?op=APPEND&permission=777&user.name=$USER&namenoderpcaddress=namenode.lxd:9000"

# READ file
curl -i "http://datanode.lxd:9864/webhdfs/v1/foo?op=OPEN&user.name=$USER&namenoderpcaddress=namenode.lxd:9000"

# STAT file
curl -i  "http://namenode.lxd:9870/webhdfs/v1/foo?op=LISTSTATUS"
curl -i  "http://namenode.lxd:9870/webhdfs/v1/foo?op=GETFILESTATUS"

# DELETE file
curl -i -X DELETE "http://namenode.lxd:9870/webhdfs/v1/foo?op=DELETE&recursive=true&user.name=$USER"

# MKDIR
curl -i -X PUT "http://namenode.lxd:9870/webhdfs/v1/thedir?op=MKDIRS&permission=777&user.name=$USER"
```

Note: The default port for WebHDFS is 9870.


### Troubleshooting

#### LXC containers fail to start

Error:
```bash
$ lxc info --show-log ubuntu
lxc namenode 20220726184019.309 WARN     cgfsng - ../src/src/lxc/cgroups/cgfsng.c:cgfsng_setup_limits:3224 - Invalid argument - Ignoring cgroup2 limits on legacy cgroup system
lxc namenode 20220726184019.881 ERROR    conf - ../src/src/lxc/conf.c:turn_into_dependent_mounts:3919 - No such file or directory - Failed to recursively turn old root mount tree into dependent mount. Continuing...
lxc namenode 20220726184019.160 ERROR    cgfsng - ../src/src/lxc/cgroups/cgfsng.c:cgfsng_mount:2131 - No such file or directory - Failed to create cgroup at_mnt 24()
....
```

Solution:
```bash
$ grep cgroup /proc/mounts
cgroup2 /sys/fs/cgroup cgroup2 rw,nosuid,nodev,noexec,relatime 0 0
none /sys/fs/cgroup/net_cls cgroup rw,relatime,net_cls 0 0

$ sudo umount /sys/fs/cgroup/net_cls
```

For more details, 
see [here](https://discuss.linuxcontainers.org/t/help-help-help-cgroup2-related-issue-on-ubuntu-jammy/14705)
and [here](https://github.com/lxc/lxd/issues/10441).

### References
* [LXC Getting Started](https://linuxcontainers.org/lxd/getting-started-cli/)
* [Verify signatures in Java](https://etzold.medium.com/elliptic-curve-signatures-and-how-to-use-them-in-your-java-application-b88825f8e926)
* [Signature Algorithms in Java](https://docs.oracle.com/javase/8/docs/technotes/guides/security/StandardNames.html#Signature)
