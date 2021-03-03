PROJECT_ID ?= kuberdrupal
RELEASE ?= {{REPO_NAME}}
BRANCH_NAME ?= $(shell git branch --show-current || echo "HEAD")
TAG_NAME ?= $(shell git describe --exact-match --tags 2>/dev/null || echo "")
COMMIT_SHA ?= $(shell git rev-parse HEAD)
COMMIT_MSG ?= $(shell /usr/bin/printf "%q " `git log --pretty=format:'%s' -1`)
HIDE_OUTPUT ?= > /dev/null

.PHONY: dependencies
.PHONY: test
.PHONY: deploy uninstall

test: test/testing test/staging test/production

test/%: dependencies
	@echo "Testing [$*]..."
	@helm lint \
		--values=values.yaml \
		--values=values.$*.yaml \
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
		--values=values.yaml \
		--values=values.$*.yaml \
		--set-string=global.env.projectId=$(PROJECT_ID) \
		--set-string=global.env.repoName=gcloud \
		--set-string=global.env.branchName=$(BRANCH_NAME) \
		--set-string=global.env.tagName=$(TAG_NAME) \
		--set-string=global.env.commitSha=$(COMMIT_SHA) \
		--set-string=global.env.commitMsg="$(COMMIT_MSG)" \
		$(RELEASE)-$* ./helmchart $(HIDE_OUTPUT)
	@echo "Success!"

deploy: deploy/testing

deploy/%: dependencies
	@helm upgrade --install \
		--namespace=$* \
		--values=values.yaml \
		--values=values.$*.yaml \
		--set-string=global.env.projectId=$(PROJECT_ID) \
		--set-string=global.env.repoName=gcloud \
		--set-string=global.env.branchName=$(BRANCH_NAME) \
		--set-string=global.env.tagName=$(TAG_NAME) \
		--set-string=global.env.commitSha=$(COMMIT_SHA) \
		--set-string=global.env.commitMsg="$(COMMIT_MSG)" \
		$(RELEASE)-$* ./helmchart

uninstall: uninstall/testing

uninstall/%: dependencies
	@helm uninstall $(RELEASE)-$* -n $*

dependencies:
	@helm dependency update ./helmchart