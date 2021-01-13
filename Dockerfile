FROM jenkins/jenkins:2.263.1-jdk11

USER root

# Allow override of UID/GID if necessary
ARG UID=1001
ARG GID=1001
# Align user IDs between EC2 host and container
RUN usermod -u 1001 jenkins && groupmod -g 1001 jenkins
RUN chown -R jenkins.jenkins /usr/share/jenkins

RUN apt-get update && apt-get install -y \
    software-properties-common

RUN apt-get update && apt-get install -y \
    sudo \
    git

RUN ln -sf /usr/share/zoneinfo/America/Los_Angeles /etc/localtime; \
    dpkg-reconfigure -f noninteractive tzdata; \
    date

RUN curl -L https://storage.googleapis.com/git-repo-downloads/repo -o /usr/local/bin/repo
RUN chmod a+x /usr/local/bin/repo

RUN mkdir -p /usr/share/jenkins/casc_configs && chown jenkins /usr/share/jenkins/casc_configs
RUN mkdir -p /usr/share/jenkins/jobDsl && chown jenkins /usr/share/jenkins/jobDsl
RUN mkdir -p /usr/share/jenkins/init.groovy.d/ && chown jenkins /usr/share/jenkins/init.groovy.d

RUN echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
RUN adduser jenkins sudo

USER jenkins

RUN /usr/local/bin/install-plugins.sh \
    amazon-ecr \
    amazon-ecs \
    ansicolor \
    artifactory \
    aws-credentials \
    aws-secrets-manager-credentials-provider \
    basic-branch-build-strategies \
    blueocean \
    blueocean-executor-info \
    build-token-root \
    build-name-setter \
    build-timeout \
    configuration-as-code \
    dark-theme \
    # Keep ec2 pinned as it often requires testing or update of the ec2-plugin.yaml \
    ec2:1.56 \
    email-ext \
    embeddable-build-status \
    generic-webhook-trigger \
    git \
    github-scm-trait-notification-context \
    google-login \
    greenballs \
    http_request \
    job-dsl \
    jqs-monitoring \
    labelled-steps \
    lockable-resources \
    logstash \
    matrix-auth \
    monitoring \
    oic-auth \
    parameterized-trigger \
    parameterized-scheduler \
    pipeline-aws \
    pipeline-github \
    pipeline-utility-steps \
    prometheus \
    rebuild \
    repo \
    role-strategy \
    slack \
    timestamper \
    valgrind \
    workflow-aggregator \
    ws-cleanup

# Filter multibranch builds based on target branch:
#    scm-filter-branch-pr \
# Use a default Jenkinsfile for repos, so no Jenkinsfile is needed:
#    pipeline-multibranch-defaults \

## The original script doesn't support incrementals well. Use a patched one if needed.
#RUN /usr/local/bin/install-plugins-inc.sh \
#    "ec2:incrementals;org.jenkins-ci.plugins;1.42-rc823.17ad3043e0e0"

# Overwrite with desired role config during image build,
# e.g. 'docker build --build-arg JENKINS_SERVER_ROLE=local' to
# use a local config (e.g. to give everyone admin access).
# Possible values: prod, test (for jenkins-test), local
#
# Use prod as default as that is the most restrictive.
ARG JENKINS_SERVER_ROLE=prod
COPY casc_configs/common/* /usr/share/jenkins/casc_configs/
COPY casc_configs/${JENKINS_SERVER_ROLE}/* /usr/share/jenkins/casc_configs/
COPY ci/jobDsl/* /usr/share/jenkins/jobDsl/

ENV CASC_JENKINS_CONFIG /usr/share/jenkins/casc_configs
