CXX := clang++
APP := gitcku
SRC := src/main.mm
BUILD_DIR := build

CXXFLAGS := -std=c++17 -Wall -Wextra -Wpedantic -fobjc-arc
LDFLAGS := -framework Foundation -lncurses

.PHONY: all clean install

all: $(BUILD_DIR)/$(APP)

$(BUILD_DIR)/$(APP): $(SRC)
	mkdir -p $(BUILD_DIR)
	$(CXX) $(CXXFLAGS) $(SRC) -o $@ $(LDFLAGS)

install: $(BUILD_DIR)/$(APP)
	install -d /usr/local/bin
	install $(BUILD_DIR)/$(APP) /usr/local/bin/$(APP)

clean:
	rm -rf $(BUILD_DIR)
