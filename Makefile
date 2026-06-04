CXX := clang++
APP := gitcku
BUILD_DIR := build
SRC_MM := src/main.mm src/App.mm src/Git.mm
SRC_CPP := src/TextUtils.cpp
OBJ := $(patsubst src/%.mm,$(BUILD_DIR)/%.o,$(SRC_MM)) \
       $(patsubst src/%.cpp,$(BUILD_DIR)/%.o,$(SRC_CPP))

CXXFLAGS := -std=c++17 -Wall -Wextra -Wpedantic -fobjc-arc
LDFLAGS := -framework Foundation -lncurses

.PHONY: all clean install

all: $(BUILD_DIR)/$(APP)

$(BUILD_DIR)/$(APP): $(OBJ)
	mkdir -p $(BUILD_DIR)
	$(CXX) $(OBJ) -o $@ $(LDFLAGS)

$(BUILD_DIR)/%.o: src/%.mm
	mkdir -p $(BUILD_DIR)
	$(CXX) $(CXXFLAGS) -c $< -o $@

$(BUILD_DIR)/%.o: src/%.cpp
	mkdir -p $(BUILD_DIR)
	$(CXX) $(CXXFLAGS) -c $< -o $@

install: $(BUILD_DIR)/$(APP)
	install -d /usr/local/bin
	install $(BUILD_DIR)/$(APP) /usr/local/bin/$(APP)

clean:
	rm -rf $(BUILD_DIR)
