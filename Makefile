.PHONY: test build package clean

test:
	@echo "Running tests..."
	@echo "Test passed" > test-results.txt
	@echo "✓ Tests completed"

build:
	@echo "Building application..."
	@echo "#!/bin/bash" > app.sh
	@echo "echo 'Hello from witness test app'" >> app.sh
	@chmod +x app.sh
	@echo "✓ Build completed"

package:
	@echo "Creating package..."
	@tar czf app.tar.gz app.sh README.md
	@echo "✓ Package created: app.tar.gz"

clean:
	@rm -f test-results.txt app.sh app.tar.gz
	@echo "✓ Cleaned up"

all: clean test build package