#!groovy
// Test install of Fedora.


script {
    library identifier: "thunderx-ci@master", retriever: legacySCM(scm)
}

String test_machine = 'gbt2s19'

pipeline {
    parameters {
        booleanParam(name: 'DOCKER_PURGE',
            defaultValue: false,
            description: 'Remove existing tci builder image and rebuild.')
        string(name: 'FEDORA_KICKSTART_URL',
            defaultValue: '',
            description: 'URL of an alternate Anaconda kickstart file.')
        booleanParam(name: 'FORCE', 
            defaultValue: false,
            description: 'Force tests to run.')
        string(name: 'FEDORA_INITRD_URL',
            //defaultValue: 'https://dl.fedoraproject.org/pub/fedora/linux/releases/30/Server/aarch64/os/images/pxeboot/initrd.img',
            defaultValue: 'https://download.fedoraproject.org/pub/fedora/linux/releases/30/Server/aarch64/os/images/pxeboot/initrd.img',
            description: 'URL of Fedora Anaconda initrd.')
        //string(name: 'FEDORA_ISO_URL', // TODO: Add iso support.
        //    defaultValue: 'https://dl.fedoraproject.org/pub/fedora/linux/releases/30/Server/aarch64/iso/Fedora-Server-netinst-aarch64-30-1.2.iso',
        //    defaultValue: 'https://download.fedoraproject.org/pub/fedora/linux/releases/30/Server/aarch64/iso/Fedora-Server-netinst-aarch64-30-1.2.iso',
        //    description: 'URL of Fedora Anaconda CD-ROM iso.')
        string(name: 'FEDORA_KERNEL_URL',
            //defaultValue: 'https://dl.fedoraproject.org/pub/fedora/linux/releases/30/Server/aarch64/os/images/pxeboot/vmlinuz',
            defaultValue: 'https://download.fedoraproject.org/pub/fedora/linux/releases/30/Server/aarch64/os/images/pxeboot/vmlinuz',
            description: 'URL of Fedora Anaconda kernel.')
        booleanParam(name: 'RUN_QEMU_TESTS',
            defaultValue: true,
            description: 'Run kernel tests in QEMU emulator.')
        booleanParam(name: 'RUN_REMOTE_TESTS',
            defaultValue: false,
            description: 'Run kernel tests on remote test machine.')
        choice(name: 'TARGET_ARCH',
            choices: "arm64\namd64\nppc64le",
            description: 'Target architecture to build for.')
        string(name: 'TEST_MACHINE',
               defaultValue: 'gbt2s19',
               description: 'test machine')
        string(name: 'PIPELINE_BRANCH',
               defaultValue: 'master',
               description: 'Branch to use for fetching the pipeline jobs')
    }

    options {
        // Timeout if no node available.
        timeout(time: 120, unit: 'MINUTES')
        //timestamps()
        buildDiscarder(logRotator(daysToKeepStr: '10', numToKeepStr: '5'))
    }

    environment {
        String tciStorePath = sh(
            returnStdout: true,
            script: "set -x; \
if [ \${TCI_STORE} ]; then \
    echo -n \${TCI_STORE}; \
else \
    echo -n /run/tci-store/\${USER}; \
fi")
        jenkinsCredsPath = "${env.tciStorePath}/jenkins_creds"
        String dockerCredsExtra = "-v ${env.jenkinsCredsPath}/group:/etc/group:ro \
        -v ${env.jenkinsCredsPath}/passwd:/etc/passwd:ro \
        -v ${env.jenkinsCredsPath}/shadow:/etc/shadow:ro \
        -v ${env.jenkinsCredsPath}/sudoers.d:/etc/sudoers.d:ro"
        String dockerSshExtra = sh(
            returnStdout: true,
            script: "set -x; \
if [ \${TCI_JENKINS} ]; then \
    echo -n ' '; \
else \
    user=\$(id --user --real --name); \
    echo -n '-v /home/\${user}/.ssh:/home/\${user}/.ssh'; \
fi")
        String dockerTag = sh(
            returnStdout: true,
            script: './docker/builder/build-builder.sh --tag').trim()
        String qemu_out = "qemu-console.txt"
        String remote_out = "${params.TEST_MACHINE}-console.txt"
        String tftp_initrd = 'f_initrd'
        String tftp_kickstart = 'f_kickstart'
        String tftp_kernel = 'f_kernel'
	String tftp_remote = 'tci-jenkins@tci1'
	String tftp_qemu = 'localhost'
    }

    agent {
        //label "${params.NODE_ARCH} && docker"
        label 'master'
    }

    stages {

        stage('setup') {
            steps { /* setup */
                tci_setup_jenkins_creds()
            }
        }

        stage('build-builder') {
             steps { /* build-builder */
                 tci_print_debug_info("start")
                 tci_print_result_header()

                 echo "${STAGE_NAME}: dockerTag=@${env.dockerTag}@"

                 sh("""#!/bin/bash -ex
export PS4='+ [${STAGE_NAME}] \${BASH_SOURCE##*/}:\${LINENO}: '

tag=${env.dockerTag}
docker images \${tag%:*}

[[ "${params.DOCKER_PURGE}" != 'true' ]] || build_args=' --purge'

./docker/builder/build-builder.sh \${build_args}

""")
                }
                post { /* build-builder */
                    cleanup {
                        echo "${STAGE_NAME}: done: ${currentBuild.currentResult}"
                   }
               }
           }

        stage('upload files') {
            agent { /* run-remote-tests */
                docker {
                    image "${env.dockerTag}"
                    args "--network host \
                        --privileged \
                        ${env.dockerCredsExtra} \
                        ${env.dockerSshExtra} \
                           "
                    reuseNode true
                        }
                    }
            

            steps {
                script {
                    sshagent (credentials: ['tci-tftp-login-key']) {
		        sh ("""#!/bin/bash
set +ex

scripts/upload-fedora-installer.sh \
	--host=${params.TEST_MACHINE} \
	--tftp-server=${env.tftp_remote} \
	--verbose
result=\${?}
set -e
if [ \${result} -eq 0 ]; then
	echo  "yes" > NeedRemoteTest
else
	echo  "no" > NeedRemoteTest
fi

set +e

scripts/upload-fedora-installer.sh \
	--host=qemu \
	--tftp-server=${env.tftp_qemu} \
	--verbose
result=\${?}
set -e
if [ \${result} -eq 0 ]; then
	echo  "yes" > NeedQemuTest
else
	echo  "no" > NeedQemuTest
fi
""")
                    }
                 }
              }
           }


        stage('parallel-test') {
            failFast false
            parallel { /* parallel-test */

                 stage('run-remote-tests') {
                     when {
                        expression { return RUN_REMOTE_TESTS == true \
                            &&  readFile('NeedRemoteTest').contains('yes')
                            }
                       }

                      agent { /* run-remote-tests */
                      docker {
                              image "${env.dockerTag}"
                              args "--network host \
                                  --privileged \
                                  ${env.dockerCredsExtra} \
                                  ${env.dockerSshExtra} \
                                    "
                                    reuseNode true
                                }
                            }

                       environment { /* run-remote-tests */
                            TCI_BMC_CREDS = credentials("${test_machine}_bmc_creds")
                           }

                       options { /* run-remote-tests */
                             timeout(time: 120, unit: 'MINUTES')
                           }

                       steps { /* run-remote-tests */
                              echo "${STAGE_NAME}: start"
                              tci_print_debug_info("${STAGE_NAME}")
                              tci_print_result_header()

                              script {
                                  sh("""#!/bin/bash -ex
export PS4='+ [${STAGE_NAME}] \${BASH_SOURCE##*/}:\${LINENO}: '

echo "--------"
printenv | sort
echo "--------"

echo "${STAGE_NAME}: TODO"
""")
                                    currentBuild.result = 'FAILURE' // FIXME.
                                }
                            }

                       post { /* run-remote-tests */
                          cleanup {
                              archiveArtifacts(
                                  artifacts: "${STAGE_NAME}-result.txt, ${env.remote_out}",
                                  fingerprint: true)
                               echo "${STAGE_NAME}: done: ${currentBuild.currentResult}"
                                }
                            }
                        }


                stage('run-qemu-tests') {
                    when {
                        expression { return params.RUN_QEMU_TESTS == true \
                            &&  readFile('NeedQemuTest').contains('yes')
                       }
                    }

                    agent { /* run-qemu-tests */
                        docker {
                            image "${env.dockerTag}"
                            args "--network host \
                                --privileged \
                                ${env.dockerCredsExtra} \
                                ${env.dockerSshExtra} \
                            "
                            reuseNode true
                        }
                    }

                    options { /* run-qemu-tests */
                        timeout(time: 120, unit: 'MINUTES')
                    }

                    steps { /* run-qemu-tests */
                        tci_print_debug_info("start")
                        tci_print_result_header()

                        sh("""#!/bin/bash
export PS4='+ [${STAGE_NAME}] \${BASH_SOURCE##*/}:\${LINENO}: '
set -ex

rm -f ${env.qemu_out}
touch ${env.qemu_out}

rm -f fedora.hda
qemu-img create -f qcow2 fedora.hda 20G

rm -f test-login-key
ssh-keygen -q -f test-login-key -N ''

scripts/run-distro-qemu-tests.sh  \
    --arch=${params.TARGET_ARCH} \
    --initrd=${env.tftp_initrd} \
    --kernel=${env.tftp_kernel} \
    --preconfig-file=${env.tftp_kickstart} \
    --out-file=${env.qemu_out} \
    --distro=fedora \
    --hda=fedora.hda \
    --ssh-key=test-login-key \
    --verbose

""")
                    }

                    post { /* run-qemu-tests */
                        success {
                            script {
                                    if (readFile("${env.qemu_out}").contains('reboot: Power down')) {
                                        echo "${STAGE_NAME}: FOUND 'reboot' message."
                                    } else {
                                        echo "${STAGE_NAME}: DID NOT FIND 'reboot' message."
                                        currentBuild.result = 'FAILURE'
                                    }
                            }
                        }
                        cleanup {
                            archiveArtifacts(
                                artifacts: "${STAGE_NAME}-result.txt, ${env.qemu_out}",
                                fingerprint: true)
                            echo "${STAGE_NAME}: done: ${currentBuild.currentResult}"
                        }
                    }
                }
            }
        }
    }
}

void tci_setup_jenkins_creds() {
    sh("""#!/bin/bash -ex
export PS4='+ [${STAGE_NAME}] \${BASH_SOURCE##*/}:\${LINENO}: '

sudo mkdir -p ${env.jenkinsCredsPath}
sudo chown \$(id --user --real --name): ${env.jenkinsCredsPath}/
sudo cp -avf /etc/group /etc/passwd /etc/shadow /etc/sudoers.d ${env.jenkinsCredsPath}/
""")
}

void tci_print_debug_info(String info) {
    sh("""#!/bin/bash -ex
echo '${STAGE_NAME}: ${info}'
whoami
id
sudo true
""")
}

void tci_print_result_header() {
    sh("""#!/bin/bash -ex

echo "node=${NODE_NAME}" > ${STAGE_NAME}-result.txt
echo "--------" >> ${STAGE_NAME}-result.txt
echo "printenv" >> ${STAGE_NAME}-result.txt
echo "--------" >> ${STAGE_NAME}-result.txt
printenv | sort >> ${STAGE_NAME}-result.txt
echo "--------" >> ${STAGE_NAME}-result.txt
""")
}


