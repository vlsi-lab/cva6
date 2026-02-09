#!/bin/bash
#
# Unified Test Runner for CVA6 Post-Quantum Crypto Tests
#
# Usage:
#   source run_tests.sh                     # Menu interattivo per selezionare i test
#   source run_tests.sh --all               # Esegue tutti i test
#   source run_tests.sh --test HQC-1        # Esegue un singolo test
#   source run_tests.sh --test HQC-1 --test ml-kem-512   # Esegue piu' test
#   source run_tests.sh --list              # Mostra i test disponibili
#

# ============================================================================
# CONFIGURAZIONE
# ============================================================================

ROOT_DIR="$(pwd)"
TESTS_DIR="${ROOT_DIR}/tests"
SIM_DIR="${ROOT_DIR}/verif/sim"
DV_TARGET="cv64a6_imac_crypto"
DV_SIMULATORS="veri-testharness"
ISS_TIMEOUT=1000000
TIME_OUT=100000000000

# Cartella risultati
RESULTS_BASE="${ROOT_DIR}/test_results"
RUN_TIMESTAMP="$(date +%Y-%m-%d)"
RESULTS_DIR="${RESULTS_BASE}/${RUN_TIMESTAMP}"

# Log file
LOG_FILE="${RESULTS_DIR}/test_run.log"

# Data odierna per trovare la cartella di output della simulazione
TODAY="$(date +%Y-%m-%d)"
SIM_OUTPUT_DIR="${SIM_DIR}/out_${TODAY}"
SIM_LOG_PATH="${SIM_OUTPUT_DIR}/veri-testharness_sim/main.${DV_TARGET}.log.iss"

# ============================================================================
# LISTA DEI TEST DISPONIBILI
# (Solo quelli con run.sh e target cv64a6_imac_crypto)
# ============================================================================

ALL_TESTS=(
    "HQC-1"
    "HQC-3"
    "HQC-5"
    "ML-DSA-2"
    "ML-DSA-3"
    "ML-DSA-5"
    "ml-kem-512"
    "ml-kem-768"
    "ml-kem-1024"
    "ml-kem-512-indcpa"
    "SPHINCS+-128f-robust"
    "SPHINCS+-128f-simple"
    "SPHINCS+-192f-robust"
    "SPHINCS+-192f-simple"
    "SPHINCS+-256f-robust"
    "SPHINCS+-256f-simple"
)

# ============================================================================
# FUNZIONI
# ============================================================================

log_msg() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg"
    echo "$msg" >> "$LOG_FILE"
}

# Determina il percorso degli header per un test.
# Controlla se esiste una sottocartella inc/ o include/, altrimenti usa la root del test.
# Il percorso e' relativo a verif/sim/ (dove viene eseguito cva6.py).
get_include_path() {
    local test_name="$1"
    local test_dir="${TESTS_DIR}/${test_name}"

    if [ -d "${test_dir}/inc" ]; then
        echo "../../tests/${test_name}/inc"
    elif [ -d "${test_dir}/include" ]; then
        echo "../../tests/${test_name}/include"
    else
        echo "../../tests/${test_name}"
    fi
}

# Trova tutti i file .c nella cartella del test (escludendo main.c).
# I percorsi sono relativi a verif/sim/.
get_source_files() {
    local test_name="$1"
    local test_dir="${TESTS_DIR}/${test_name}"
    local sources=""

    for cfile in "${test_dir}"/*.c; do
        local fname
        fname="$(basename "$cfile")"
        if [ "$fname" != "main.c" ]; then
            sources="${sources} ../../tests/${test_name}/${fname}"
        fi
    done

    echo "$sources"
}

# Esegue un singolo test
run_single_test() {
    local test_name="$1"
    local test_dir="${TESTS_DIR}/${test_name}"
    local test_num="$2"
    local test_total="$3"

    log_msg "================================================================"
    log_msg "TEST [${test_num}/${test_total}]: ${test_name} - INIZIO"
    log_msg "================================================================"

    # Verifica che la cartella del test esista
    if [ ! -d "$test_dir" ]; then
        log_msg "ERRORE: La cartella del test non esiste: ${test_dir}"
        log_msg "TEST [${test_num}/${test_total}]: ${test_name} - FALLITO (cartella non trovata)"
        return 1
    fi

    # Verifica che main.c esista
    if [ ! -f "${test_dir}/main.c" ]; then
        log_msg "ERRORE: main.c non trovato in: ${test_dir}"
        log_msg "TEST [${test_num}/${test_total}]: ${test_name} - FALLITO (main.c non trovato)"
        return 1
    fi

    # Ottieni i file sorgente e il percorso degli header
    local source_files
    source_files="$(get_source_files "$test_name")"
    local include_path
    include_path="$(get_include_path "$test_name")"

    log_msg "Sorgenti: ${source_files}"
    log_msg "Include path: ${include_path}"

    # Esegui il test da verif/sim/
    cd "${SIM_DIR}" || {
        log_msg "ERRORE: Impossibile entrare in ${SIM_DIR}"
        cd "${ROOT_DIR}"
        return 1
    }

    log_msg "Esecuzione cva6.py per ${test_name}..."

    python3 cva6.py --target="${DV_TARGET}" --iss="${DV_SIMULATORS}" --iss_yaml=cva6.yaml \
        --c_tests "../../tests/${test_name}/main.c" \
        --iss_timeout "${ISS_TIMEOUT}" --issrun_opts="+time_out=${TIME_OUT}" \
        --linker=../tests/custom/common/test.ld \
        --gcc_opts="-static -mcmodel=medany -fvisibility=hidden -O2 \
        -funroll-loops -finline-functions \
        -nostartfiles -g ../tests/custom/common/syscalls.c \
        ../tests/custom/common/crt.S \
        ${source_files} \
        -lgcc -fstack-usage \
        -I../tests/custom/env -I../tests/custom/common -I${include_path}" \
        >> "$LOG_FILE" 2>&1

    local exit_code=$?

    cd "${ROOT_DIR}" || true

    # Gestione output: sposta e rinomina il file di log della simulazione
    # Ricalcola la data perche' il test potrebbe essere durato giorni
    local current_date
    current_date="$(date +%Y-%m-%d)"
    local current_sim_output="${SIM_DIR}/out_${current_date}/veri-testharness_sim/main.${DV_TARGET}.log.iss"

    if [ -f "$current_sim_output" ]; then
        local dest_file="${RESULTS_DIR}/${test_name}.log.iss"
        cp "$current_sim_output" "$dest_file"
        log_msg "Output copiato in: ${dest_file}"
    else
        log_msg "ATTENZIONE: File di output simulazione non trovato: ${current_sim_output}"
        # Prova anche con la data di inizio del run
        if [ "$current_date" != "$TODAY" ] && [ -f "$SIM_LOG_PATH" ]; then
            local dest_file="${RESULTS_DIR}/${test_name}.log.iss"
            cp "$SIM_LOG_PATH" "$dest_file"
            log_msg "Output copiato (data inizio run) in: ${dest_file}"
        fi
    fi

    # Risultato
    if [ $exit_code -eq 0 ]; then
        log_msg "TEST [${test_num}/${test_total}]: ${test_name} - COMPLETATO CON SUCCESSO (exit code: ${exit_code})"
    else
        log_msg "TEST [${test_num}/${test_total}]: ${test_name} - FALLITO (exit code: ${exit_code})"
    fi

    return $exit_code
}

# Mostra il menu interattivo per selezionare i test
show_menu() {
    echo ""
    echo "============================================"
    echo "  CVA6 Post-Quantum Crypto Test Runner"
    echo "============================================"
    echo ""
    echo "Test disponibili:"
    echo ""
    local i=1
    for test in "${ALL_TESTS[@]}"; do
        printf "  %2d) %s\n" "$i" "$test"
        i=$((i + 1))
    done
    echo ""
    echo "   a) Esegui TUTTI i test"
    echo "   q) Esci"
    echo ""
    echo "Seleziona i test da eseguire (numeri separati da spazio, es: 1 3 5):"
    read -r selection

    if [ "$selection" = "q" ]; then
        echo "Uscita."
        return 1
    fi

    SELECTED_TESTS=()

    if [ "$selection" = "a" ]; then
        SELECTED_TESTS=("${ALL_TESTS[@]}")
    else
        for num in $selection; do
            if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le "${#ALL_TESTS[@]}" ]; then
                SELECTED_TESTS+=("${ALL_TESTS[$((num - 1))]}")
            else
                echo "ATTENZIONE: '$num' non e' un numero valido, ignorato."
            fi
        done
    fi

    if [ ${#SELECTED_TESTS[@]} -eq 0 ]; then
        echo "Nessun test selezionato."
        return 1
    fi

    return 0
}

# ============================================================================
# PARSING ARGOMENTI
# ============================================================================

SELECTED_TESTS=()
SHOW_LIST=0

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --all)
                SELECTED_TESTS=("${ALL_TESTS[@]}")
                shift
                ;;
            --test)
                if [ -n "$2" ]; then
                    # Verifica che il test esista nella lista
                    local found=0
                    for t in "${ALL_TESTS[@]}"; do
                        if [ "$t" = "$2" ]; then
                            found=1
                            break
                        fi
                    done
                    if [ $found -eq 1 ]; then
                        SELECTED_TESTS+=("$2")
                    else
                        echo "ERRORE: Test '$2' non trovato. Usa --list per vedere i test disponibili."
                        return 1
                    fi
                    shift 2
                else
                    echo "ERRORE: --test richiede un argomento."
                    return 1
                fi
                ;;
            --list)
                SHOW_LIST=1
                shift
                ;;
            --help|-h)
                echo "Uso:"
                echo "  source run_tests.sh                              # Menu interattivo"
                echo "  source run_tests.sh --all                        # Tutti i test"
                echo "  source run_tests.sh --test NOME                  # Un singolo test"
                echo "  source run_tests.sh --test NOME1 --test NOME2   # Piu' test"
                echo "  source run_tests.sh --list                       # Lista test disponibili"
                return 1
                ;;
            *)
                echo "ERRORE: Argomento sconosciuto: $1"
                echo "Usa --help per l'uso."
                return 1
                ;;
        esac
    done
    return 0
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    # Verifica di essere nella root del progetto
    if [ ! -d "${TESTS_DIR}" ] || [ ! -d "${SIM_DIR}" ]; then
        echo "ERRORE: Questo script deve essere eseguito dalla root del progetto cva6."
        echo "  Directory corrente: $(pwd)"
        return 1
    fi

    # Parsing argomenti
    parse_args "$@" || return 1

    # Mostra lista e esci
    if [ $SHOW_LIST -eq 1 ]; then
        echo ""
        echo "Test disponibili:"
        for test in "${ALL_TESTS[@]}"; do
            echo "  - ${test}"
        done
        return 0
    fi

    # Se nessun test selezionato via argomenti, mostra il menu
    if [ ${#SELECTED_TESTS[@]} -eq 0 ]; then
        show_menu || return 1
    fi

    # Crea la cartella dei risultati
    mkdir -p "$RESULTS_DIR"

    # Source dell'environment setup
    source "${SIM_DIR}/setup-env.sh"
    export DV_SIMULATORS="${DV_SIMULATORS}"

    # Intestazione del log
    log_msg "============================================"
    log_msg "  CVA6 Test Runner - Inizio sessione"
    log_msg "============================================"
    log_msg "Data: $(date)"
    log_msg "Cartella risultati: ${RESULTS_DIR}"
    log_msg "Test selezionati (${#SELECTED_TESTS[@]}):"
    for test in "${SELECTED_TESTS[@]}"; do
        log_msg "  - ${test}"
    done
    log_msg ""

    # Contatori
    local total=${#SELECTED_TESTS[@]}
    local passed=0
    local failed=0
    local failed_tests=()
    local passed_tests=()

    # Esecuzione dei test
    local i=1
    for test_name in "${SELECTED_TESTS[@]}"; do
        run_single_test "$test_name" "$i" "$total"
        if [ $? -eq 0 ]; then
            passed=$((passed + 1))
            passed_tests+=("$test_name")
        else
            failed=$((failed + 1))
            failed_tests+=("$test_name")
        fi
        i=$((i + 1))
        log_msg ""
    done

    # Riepilogo finale
    log_msg "============================================"
    log_msg "  RIEPILOGO FINALE"
    log_msg "============================================"
    log_msg "Totale test:   ${total}"
    log_msg "Completati:    ${passed}"
    log_msg "Falliti:       ${failed}"
    log_msg ""

    if [ ${#passed_tests[@]} -gt 0 ]; then
        log_msg "Test completati con successo:"
        for t in "${passed_tests[@]}"; do
            log_msg "  [OK]   ${t}"
        done
    fi

    if [ ${#failed_tests[@]} -gt 0 ]; then
        log_msg ""
        log_msg "Test falliti:"
        for t in "${failed_tests[@]}"; do
            log_msg "  [FAIL] ${t}"
        done
    fi

    log_msg ""
    log_msg "Log completo: ${LOG_FILE}"
    log_msg "Risultati in:  ${RESULTS_DIR}"
    log_msg "============================================"
    log_msg "  Fine sessione: $(date)"
    log_msg "============================================"

    # Ritorna alla root
    cd "${ROOT_DIR}" || true

    return $failed
}

# Esegui
main "$@"
