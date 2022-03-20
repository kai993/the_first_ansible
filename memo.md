# Ansible memo

## local(Mac)
```bash
❯ pip3 --version
pip 21.1.3 from /usr/local/lib/python3.9/site-packages/pip (python 3.9)

❯ pip3 install ansible

❯ ansible --version
ansible [core 2.12.3]
  config file = None
...
  python version = 3.9.6 (default, Jun 29 2021, 05:25:02) [Clang 12.0.5 (clang-1205.0.22.9)]
  jinja version = 3.0.3
  libyaml = True
```

## リモートサーバー(Centos7)
```bash
@mac
❯ grep -v -e '#' -e '^\s*$' Vagrantfile
Vagrant.configure("2") do |config|
  config.vm.box = "centos/7"
  config.vm.network "private_network", ip: "192.168.56.10"
  config.vm.hostname = "centos7.sample.co.jp"
end

❯ basename $(pwd)
centos7

❯ vagrant ssh-config
Host default
  HostName 127.0.0.1
  User vagrant
  Port 2222
  UserKnownHostsFile /dev/null
  StrictHostKeyChecking no
  PasswordAuthentication no
  IdentityFile /Users/kwatabiki/ansible/centos7/.vagrant/machines/default/virtualbox/private_key
  IdentitiesOnly yes
  LogLevel FATAL

❯ vagrant up

# ssh接続できるようにする
❯ vagrant ssh-config --host centos7.sample.co.jp >> ~/.ssh/config

# ssh接続できることを確認
❯ ssh -A centos7.sample.co.jp
[vagrant@centos7 ~]$
```

## ansibleコマンドで接続できるか確認

```bash
@mac
❯ cat hosts
testserver ansible_ssh_host=centos7.sample.co.jp

# OK!
❯ ansible testserver -i hosts -m ping
testserver | SUCCESS => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python"
    },
    "changed": false,
    "ping": "pong"
}
```

## ansible.cfg

インベントリファイルに記載するのではなく設定ファイルに記載することでデフォルトで設定することができる。  
設定できるものは[ここ](https://docs.ansible.com/ansible/2.9_ja/reference_appendices/config.html#ansible-configuration-settings)を参照

```bash
@mac
❯ cat ansible.cfg
[defaults]
inventory = hosts

❯ cat hosts
testserver ansible_ssh_host=centos7.sample.co.jp

❯ ansible testserver -m ping
testserver | SUCCESS => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python"
    },
    "changed": false,
    "ping": "pong"
}

# 全てのサーバーに対して実行する場合はallとする
❯ ansible all -m ping
testserver | SUCCESS => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python"
    },
    "changed": false,
    "ping": "pong"
}
```

## 任意のコマンドを使う
commandモジュールと`-a`オプションで任意のコマンドを実行することが可能

```bash
❯ ansible testserver -m command -a uptime
testserver | CHANGED | rc=0 >>
 07:38:14 up 28 min,  2 users,  load average: 0.00, 0.01, 0.02

❯ ansible testserver -m command -a "tail -n 5 /var/log/dmesg"
testserver | CHANGED | rc=0 >>
[    3.000978] RPC: Registered tcp NFSv4.1 backchannel transport module.
[    3.102363] alg: No test for __gcm-aes-aesni (__driver-gcm-aes-aesni)
[    3.113798] alg: No test for __generic-gcm-aes-aesni (__driver-generic-gcm-aes-aesni)
[    3.145639] Adding 2097148k swap on /swapfile.  Priority:-2 extents:1 across:2097148k FS
[    3.218571] intel_pmc_core:  initialized

# -bフラグを渡すとsudoしてrootになる
❯ ansible testserver -a "ls /root"
testserver | FAILED | rc=2 >>
ls: cannot open directory /root: Permission deniednon-zero return code

❯ ansible testserver -b -a "ls /root"
testserver | CHANGED | rc=0 >>
anaconda-ks.cfg
original-ks.cfg
```

