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
    PACKAGE_ID = "0x7782e9a5ddff169f113b1ce9527752789dec1c5933fdd270d069fae231388e34"
    GAME_ID = "0xabea37c39fcee0d16d8dc127cb031343233c3d41dd84c37d442d56815f57e20b"
    COIN_ID = "0x9ca01b4bc03ff17c063d5f8fa2b25e5121de5a8cd4798b227e1b064ef8b7fe71"
    MY_ADDRESS = "0x7763265f11db8be13a63b8dc12da971da739704d818440e51ded4c8478424ed0"
    
    create_command = f"sui client ptb --assign sender @{MY_ADDRESS} --move-call {PACKAGE_ID}::betting::test @{GAME_ID}"
    output = run_command(create_command)
    print(output)

if __name__ == "__main__":
    main()