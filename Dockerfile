# syntax=docker/dockerfile:1

# Updated July 28, 2025

# The line above is from docker init command.  It has to be the first line in the Dockerfile in order to take effect. "Declaring a syntax version lets you automatically use the latest Dockerfile version without having to upgrade BuildKit or Docker Engine, or even use a custom Dockerfile implementation." (https://docs.docker.com/go/dockerfile-reference/) 


# ************** SOURCES ****************

# This Dockerfile is compiled from the following "best practices":

# - DOCKER INIT command (DI).  For more info see: https://docs.docker.com/reference/cli/docker/init/
# - STRAPI DOCKER docs (SD): https://docs.strapi.io/dev-docs/installation/docker
# - BRET FISHER Docker/Node repo (BF): https://github.com/BretFisher/nodejs-rocks-in-docker/blob/main/README.md


# ************** BASE IMAGE (Follows BF Best Practices) ****************

# CHAINGUARD IMAGES: From BF repo and YouTube video(https://www.youtube.com/watch?v=GEPW008G250): 
# Chainguard base image is most secure and very small.  For more on Chaingaurd image details see: https://edu.chainguard.dev/chainguard/chainguard-images/reference/node-lts/tags_history/

# Chainguard images do not include the ibvips-dev libraries needed by Strapi for image processing.  Also,the current chainguard Node image is not supported by Strapi.  We may chose to revisit chaingaurd images for production, but not for development.

# BF SIDE LOAD STRATEGY: (1) Use a secure, widely supported image for Base OS (Ubuntu); and (2) copy the official Node binaries directly into the base image.  Results in a small, secure, well-supported image (https://github.com/BretFisher/nodejs-rocks-in-docker/blob/main/dockerfiles/ubuntu-copy.Dockerfile).

# Latest version of Node supported by Strapi 5 is 22.17.1 as of July 28, 2025
# https://hub.docker.com/_/node/tags?name=22.17-bullseye-slim
ARG NODE=node:22.17-bullseye-slim@sha256:741a60f76e79ab4080ebb10d24ec0c2aa4527fc44e33a8d609c416cc351b4fff

# Latest version of Ubuntu with zero CVEs
# https://hub.docker.com/_/ubuntu/tags?name=oracular
ARG BASE=ubuntu:oracular-20250619@sha256:cdf755952ed117f6126ff4e65810bf93767d4c38f5c7185b50ec1f1078b464cc


FROM ${NODE} AS node
FROM ${BASE}


# ************** ENTRY POINT: TINI ****************

# Node is not good at kernel signal handling within Docker. Node does not stop running when you stop the container.  You have to wait 10 seconds for Docker to kill the process and stop the container. 
# BF recommends that we use tini (https://github.com/krallin/tini) as the ENTRYPOINT for node apps in Docker.  
# Strapi recommends PM2 (https://www.npmjs.com/package/pm2) as a process manager for Strapi "to keep your Strapi application running and to reload it without downtime" (https://docs-v4.strapi.io/dev-docs/deployment/process-manager).

# NOTE: TINI_VERSION and TINI_ARCH not working for some reason, so version for now we are hardcoding these values
# https://github.com/krallin/tini/releases/download/v${TINI_VERSION}/tini-${TINI_ARCH}

# We use the ARM/64 version for Macs with Apple chip, but we will need to use AMD/64 version on AWS.

ARG TINI_VERSION=v0.19.0
ARG TINI_ARCH=arm64

ADD --chmod=755 https://github.com/krallin/tini/releases/download/v0.19.0/tini-arm64 /tini
ENTRYPOINT ["/tini", "--"]


# ************** SIDE LOAD OFFICIAL NODE BINARIES ****************

#Copy Node binaries from official Node image
COPY --from=node /usr/local/include/ /usr/local/include/
COPY --from=node /usr/local/lib/ /usr/local/lib/
COPY --from=node /usr/local/bin/ /usr/local/bin/

#fix simlinks for npx, yarn, and pnpm
# RUN corepack disable && corepack enable


# ************** BUILD STRAPI (Follows SD Best Practices) ****************

# Strapi 5 supports Node version 22
ARG NODE_VERSION=22.13.1

# Installing libvips-dev for sharp Compatibility
RUN apt update && apt install build-essential gcc autoconf automake zlib1g-dev libpng-dev nasm bash  libvips-dev git -y

ARG NODE_ENV=development
ENV NODE_ENV=${NODE_ENV}

# NOTE: This Dockerfile uses NPM. Strapi v5.10 officially supports PNPM but the container crashes when we attempt to run this image.  The errors say it cannot find the Sharp Compatibility library.  For this reason, we are sticking to NPM.

WORKDIR /opt/
COPY package.json package-lock.json ./
RUN npm install -g node-gyp
RUN npm config set fetch-retry-maxtimeout 600000 -g && npm install
ENV PATH=/opt/node_modules/.bin:$PATH

# create node user and group.  This user is part of the official node package, but because we are side-loading Node we have to create it.
RUN groupadd --gid 1001 node \
    && useradd --uid 1001 --gid node --shell /bin/bash --create-home node

WORKDIR /opt/app
COPY . .
RUN chown -R node:node /opt/app
USER node
#build the Admin panel
RUN ["npm", "run", "build"]
EXPOSE 1337
#launch the Strapi server in development mode
CMD ["npm", "run", "develop"]
