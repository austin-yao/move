import subprocess
import json
import sys

def run_command(command):
    result = subprocess.run(command, shell=True, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"Error running command: {command}")
        print(result.returncode)
        print(result.stderr)
        sys.exit(1)
    print(result.stdout)
    return result.stdout

def main():
    print("Hello")


if __name__ == "__main__":
    main()