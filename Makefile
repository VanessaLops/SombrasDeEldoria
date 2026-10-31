PROJECT      := SombrasDeEldoria.xcodeproj
SCHEME       := SombrasDeEldoria
BUNDLE_ID    := com.neu.sombrasdeeldoria
SIMULATOR    ?= iPhone 18 Pro
DERIVED_DATA := .build/DerivedData
APP_PATH     := $(DERIVED_DATA)/Build/Products/Debug-iphonesimulator/$(SCHEME).app
PACKAGE_DIR  := Packages/SombrasKit

.DEFAULT_GOAL := help
.PHONY: help core test build run open clean

help: ## Lista os comandos
	@grep -E '^[a-z]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  make %-8s %s\n", $$1, $$2}'

core: ## Compila só a simulação pura (macOS, segundos)
	cd $(PACKAGE_DIR) && swift build --target SimCore

test: ## Testes do núcleo, inclusive partidas 5v5 inteiras entre bots (otimizado: ~20 s)
	cd $(PACKAGE_DIR) && swift test -c release -Xswiftc -enable-testing

build: ## Compila o app para o Simulador
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination 'platform=iOS Simulator,name=$(SIMULATOR)' \
		-derivedDataPath $(DERIVED_DATA) -quiet build

run: build ## Compila, instala e abre no Simulador
	xcrun simctl boot "$(SIMULATOR)" 2>/dev/null || true
	@open -a Simulator 2>/dev/null \
		|| open "$$(xcode-select -p)/../Applications/DeviceHub.app" 2>/dev/null \
		|| echo "Aviso: não achei Simulator nem DeviceHub; o app roda mesmo assim."
	xcrun simctl install "$(SIMULATOR)" $(APP_PATH)
	xcrun simctl launch "$(SIMULATOR)" $(BUNDLE_ID)

open: ## Abre o projeto no Xcode
	open $(PROJECT)

clean: ## Remove artefatos de build
	rm -rf .build $(PACKAGE_DIR)/.build
