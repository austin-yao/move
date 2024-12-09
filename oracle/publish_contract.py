import subprocess
import json
import sys

MY_ADDRESS = "0x7763265f11db8be13a63b8dc12da971da739704d818440e51ded4c8478424ed0"
MODULE = "betting"
PACKAGE_ID = None
INIT_ID = None
COIN_ID = None
GAME_ID = None

# Function to run a command and capture its output
def run_command(command):
    result = subprocess.run(command, shell=True, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"Error running command: {command}")
        print(result.returncode)
        print(result.stderr)
        print(result.stdout)
        sys.exit(1)
    print(result.stdout)
    return result.stdout

def line_break():
    print("\n--------------------------------------\n")

def main():
    print("Starting up!")
    
    # Step 1
    print("Step 1: Publishing module: ")
    publish_command = f"sui client publish --skip-dependency-verification --json"
    publish_output = run_command(publish_command)
    
    line_break()
    
    # Step 2
    print("Step 2: Retrieving packageID and initializationCap")
    try:
        publish_json = json.loads(publish_output)
        for d in publish_json["objectChanges"]:
            if d["type"] == "published":
                PACKAGE_ID = d["packageId"]
            elif "objectType" in d:
                if "InitializationCap" in d["objectType"]:
                    INIT_ID = d["objectId"]
                elif "Coin" in d["objectType"]:
                    COIN_ID = d["objectId"]
                    
        if PACKAGE_ID == None:
            print("No Package ID found")
            sys.exit(1)
        
        if INIT_ID == None:
            print("No Initialization Cap found")
            sys.exit(1)
        
        if COIN_ID == None:
            print("No Coin ID found")
            sys.exit(1)
            
        print(f"PackageID: {PACKAGE_ID}")
        print(f"InitializationCap: {INIT_ID}")
    except json.JSONDecodeError:
        print("Error decoding json in Step 2")
        sys.exit(1)
        
    line_break()
        
    print("Step 3: Initializing Contract")
    initialize_command = f"sui client ptb --assign sender @{MY_ADDRESS} --move-call {PACKAGE_ID}::{MODULE}::initialize_contract @{INIT_ID} @{COIN_ID} --json"
    initialize_output = run_command(initialize_command)
    try:
        initialize_json = json.loads(initialize_output)
        COIN_ID = None
        for d in initialize_json["objectChanges"]:
            if "objectType" in d:
                if "Coin" in d["objectType"]:
                    COIN_ID = d["objectId"]
                elif "GameData" in d["objectType"]:
                    GAME_ID = d["objectId"]
        
        if GAME_ID == None:
            print("No Game ID found")
            sys.exit(1)
            
        if COIN_ID == None:
            print("No Coin ID found")
            sys.exit(1)
            
        print(f"Game ID: {GAME_ID}")
    except json.JSONDecodeError:
        print("Error decoding json in Step 3")
        sys.exit(1)
    
    line_break()
    
    # print("Step 4: Creating a Bet")
    # create_command = f"sui client ptb --gas-budget {GAS_BUDGET} --assign sender @{MY_ADDRESS} --move-call {PACKAGE_ID}::{MODULE}::create_bet @{GAME_ID} @{MY_ADDRESS} \"\'Does this work\'\" 50 50 1 1233333 @{COIN_ID} --json"
    # create_output = run_command(create_command)
    
    line_break()

if __name__ == "__main__":
    main()