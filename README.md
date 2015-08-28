openshift-local-setup
==================
localsetup script for Origin (OSEv3)

Precautions
----------

This is NOT official package and please take full responsibility for your actions.

Tested environment
----------

- Fedora 21 or later
- RHEL 7.1
- CentOS 7.1 (docker-1.7.1-108.el7.centos.x86_64/go1.4.2)

**NOTE** It depends on origin's version. At the moment(Origin v1.0.4 / OSE v3.0.1.0), it needs golang(>1.4), docker(>1.6) and git.

Quick start
----------

##### 1. Stop process which is using following ports 

~~~
80 443 4001 7001 8443
~~~

##### 2. Clone origin repository.

~~~
cd /tmp
git clone https://github.com/openshift/origin.git
~~~

##### 3. Get this script.

~~~
wget https://raw.githubusercontent.com/nak3/openshift-local-setup/master/openshift-local-setup.sh
~~~

##### 4. Run as root user.

~~~
bash openshift-local-setup.sh
~~~

##### 5. Open another terminal and run following command.

**NOTE** This is an ***example***. You can see your output in setp4.
~~~
export PATH="/tmp/origin/_output/local/go/bin/:$PATH"
alias oc="oc --config=/tmp/origin/openshift.local.config/master/admin.kubeconfig" 
alias oadm="oadm --config=/tmp/origin/openshift.local.config/master/admin.kubeconfig"
source /tmp/origin/rel-eng/completions/bash/oc
~~~

##### 6. Wait running docker-registry and router

~~~
$ oc get pod
NAME                           READY     STATUS       RESTARTS   AGE
docker-registry-1-nwayw        1/1       Running      0          1h
router-1-ocp74                 1/1       Running      0          1h
~~~

##### 7. Now you can use your OpenShift!

Login and create project.

~~~
oadm policy add-role-to-user admin joe
oc login -u joe -p foo
oc new-project demoproject
~~~

##### 8. Hello World!

~~~
oc new-app https://github.com/nak3/helloworld-v3.git -l app=hello
curl `oc get svc |grep helloworld-v3 |awk '{print $2":"$4}' | sed -e 's/\/.*//'`
Hello world
~~~

Contact
----------

If you have any question, comment or request, please tell me by following E-mail address in English or Japanese.

Mail To: <nakayamakenjiro@gmail.com> (Kenjiro Nakayama)
