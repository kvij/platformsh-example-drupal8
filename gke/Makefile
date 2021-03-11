CHART ?= ./helmchart
PROJECT_ID ?= kuberdrupal
RELEASE ?= {{REPO_NAME}}
BRANCH_NAME ?= $(shell git branch --show-current || echo "HEAD")
TAG_NAME ?= $(shell git describe --exact-match --tags 2>/dev/null || echo "")
COMMIT_SHA ?= $(shell git rev-parse HEAD)
COMMIT_MSG ?= $(shell /usr/bin/printf "%q " `git log --pretty=format:'%s' -1`)
HIDE_OUTPUT ?= > /dev/null
CONTEXT_SWITCH_SCRIPT_DIR ?= ../scripts/helm

.PHONY: dependencies
.PHONY: test
.PHONY: deploy uninstall deploy/all uninstall/all
.PHONY: context

test: test/testing test/staging test/prod

test/%: context/% dependencies
	@echo "Testing [$*]..."
	@helm lint \
		--values=${CHART}/values.yaml \
		--values=${CHART}/values.$*.yaml \
		--set-string=global.env.projectId=$(PROJECT_ID) \
		--set-string=global.env.repoName=gcloud \
		--set-string=global.env.branchName=$(BRANCH_NAME) \
		--set-string=global.env.tagName=$(TAG_NAME) \
		--set-string=global.env.commitSha=$(COMMIT_SHA) \
		--set-string=global.env.commitMsg="$(COMMIT_MSG)" \
		./helmchart
	@helm upgrade --install \
		--dry-run \
		--namespace=$* \
		--values=${CHART}/values.yaml \
		--values=${CHART}/values.$*.yaml \
		--set-string=global.env.projectId=$(PROJECT_ID) \
		--set-string=global.env.repoName=gcloud \
		--set-string=global.env.branchName=$(BRANCH_NAME) \
		--set-string=global.env.tagName=$(TAG_NAME) \
		--set-string=global.env.commitSha=$(COMMIT_SHA) \
		--set-string=global.env.commitMsg="$(COMMIT_MSG)" \
		$(RELEASE)-$* ${CHART} $(HIDE_OUTPUT)
	@echo "Success!"

deploy/all: deploy/testing deploy/staging deploy/prod

deploy/%: context/% dependencies
	@helm upgrade --install \
		--namespace=$* \
		--values=${CHART}/values.yaml \
		--values=${CHART}/values.$*.yaml \
		--set-string=global.env.projectId=$(PROJECT_ID) \
		--set-string=global.env.repoName=gcloud \
		--set-string=global.env.branchName=$(BRANCH_NAME) \
		--set-string=global.env.tagName=$(TAG_NAME) \
		--set-string=global.env.commitSha=$(COMMIT_SHA) \
		--set-string=global.env.commitMsg="$(COMMIT_MSG)" \
		$(RELEASE)-$* ${CHART}

uninstall/all: uninstall/testing uninstall/staging uninstall/prod

uninstall/%: context/% dependencies
	@helm uninstall $(RELEASE)-$* -n $*

dependencies:
	@helm dependency update ${CHART}

context:
	@$(CONTEXT_SWITCH_SCRIPT_DIR)/switch_context.sh
context/%:
	@$(CONTEXT_SWITCH_SCRIPT_DIR)/switch_context.sh $*
