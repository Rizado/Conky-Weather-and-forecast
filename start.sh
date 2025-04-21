#!/bin/bash

# Bepaal het pad naar de Conky-map
CONKY_DIR=$(dirname "$(readlink -f "$0")")

# Function to check if required fonts are installed
check_fonts() {
    local fonts=("ChopinScript" "DejaVu Serif")
    local missing_fonts=()

    for font in "${fonts[@]}"; do
        if ! fc-list | grep -q "$font"; then
            echo "Font '$font' not installed"
            missing_fonts+=("$font")
        fi
    done

    if [ ${#missing_fonts[@]} -gt 0 ]; then
        echo "Warning: Some required fonts are missing. Install them for proper display."
        return 1
    else
        echo "All required fonts are installed."
        return 0
    fi
}
#!/bin/bash

# Functie om afhankelijkheden te controleren
check_dependencies() {
    echo "Controleer of alle afhankelijkheden zijn geïnstalleerd..."
    
    # Voeg hier de lijst met vereiste afhankelijkheden toe
    local dependencies=("jq" "lua" "curl" "wget" "conky")
    local missing=()

    for dep in "${dependencies[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done

    if [ ${#missing[@]} -eq 0 ]; then
        echo "Alle afhankelijkheden zijn geïnstalleerd."
    else
        echo "De volgende afhankelijkheden ontbreken: ${missing[@]}"
        echo "Installeer deze afhankelijkheden en probeer het opnieuw."
        exit 1
    fi
}

# Aanroepen van de functie
check_dependencies
check_fonts

if pidof conky > /dev/null; then
    killall conky
fi

# Start Conky met de juiste configuratie en log fouten
cd $CONKY_DIR
conky -c ./conky.conf &

exit 0
