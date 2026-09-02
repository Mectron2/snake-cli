#!/usr/bin/env bash

# A small terminal Snake game with no dependencies beyond Bash and standard tty tools.

PROGRAM_NAME="${0##*/}"
DEFAULT_WIDTH=40
DEFAULT_HEIGHT=20
DEFAULT_SPEED=8
MIN_WIDTH=10
MIN_HEIGHT=6

COLOR_RESET=$'\033[0m'
COLOR_BORDER=$'\033[36m'
COLOR_TEXT=$'\033[1;33m'
COLOR_SNAKE=$'\033[32m'
COLOR_HEAD=$'\033[1;32m'
COLOR_FOOD=$'\033[31m'

WIDTH=$DEFAULT_WIDTH
HEIGHT=$DEFAULT_HEIGHT
SPEED=$DEFAULT_SPEED
SEED=

snake_x=()
snake_y=()
direction="right"
next_direction="right"
food_x=0
food_y=0
score=0
game_over_reason=
old_stty=

usage() {
    cat <<EOF
Usage: $PROGRAM_NAME [options]

Play Snake in your terminal. The snake grows when it eats the food.

Options:
  -w, --width N       Board width (default: $DEFAULT_WIDTH)
  -h, --height N      Board height (default: $DEFAULT_HEIGHT)
  -s, --speed N       Moves per second, from 1 to 30 (default: $DEFAULT_SPEED)
      --seed N        Use a repeatable random seed
      --test          Run built-in non-interactive checks
      --help          Show this help

Controls:
  Arrow keys or W/A/S/D   Change direction
  Q                       Quit
EOF
}

fail() {
    printf 'Error: %s\n' "$*" >&2
    exit 2
}

is_integer() {
    [[ $1 =~ ^[0-9]+$ ]]
}

decimal_value() {
    printf '%d' "$((10#$1))"
}

parse_options() {
    while (($#)); do
        case $1 in
            -w|--width)
                (($# >= 2)) || fail "$1 requires a value"
                is_integer "$2" || fail "width must be a positive integer"
                WIDTH=$(decimal_value "$2")
                shift 2
                ;;
            -h|--height)
                (($# >= 2)) || fail "$1 requires a value"
                is_integer "$2" || fail "height must be a positive integer"
                HEIGHT=$(decimal_value "$2")
                shift 2
                ;;
            -s|--speed)
                (($# >= 2)) || fail "$1 requires a value"
                is_integer "$2" || fail "speed must be an integer"
                SPEED=$(decimal_value "$2")
                shift 2
                ;;
            --seed)
                (($# >= 2)) || fail "$1 requires a value"
                is_integer "$2" || fail "seed must be an integer"
                SEED=$(decimal_value "$2")
                shift 2
                ;;
            --test)
                run_tests
                exit 0
                ;;
            --help|-\?)
                usage
                exit 0
                ;;
            *)
                fail "unknown option: $1 (try --help)"
                ;;
        esac
    done

    ((WIDTH >= MIN_WIDTH)) || fail "width must be at least $MIN_WIDTH"
    ((HEIGHT >= MIN_HEIGHT)) || fail "height must be at least $MIN_HEIGHT"
    ((SPEED >= 1 && SPEED <= 30)) || fail "speed must be between 1 and 30"
}

cell_is_snake() {
    local x=$1 y=$2 index
    for index in "${!snake_x[@]}"; do
        if ((snake_x[index] == x && snake_y[index] == y)); then
            return 0
        fi
    done
    return 1
}

place_food() {
    local free_cells=() x y index choice
    for ((y = 0; y < HEIGHT; y++)); do
        for ((x = 0; x < WIDTH; x++)); do
            cell_is_snake "$x" "$y" || free_cells+=("$x,$y")
        done
    done

    ((${#free_cells[@]})) || return 1
    choice=$((RANDOM % ${#free_cells[@]}))
    IFS=, read -r food_x food_y <<< "${free_cells[choice]}"
    return 0
}

reset_game() {
    snake_x=()
    snake_y=()
    local center_x=$((WIDTH / 2)) center_y=$((HEIGHT / 2))
    snake_x+=("$((center_x - 2))" "$((center_x - 1))" "$center_x")
    snake_y+=("$center_y" "$center_y" "$center_y")
    direction=right
    next_direction=right
    score=0
    game_over_reason=
    place_food || game_over_reason="The board is full."
}

set_direction() {
    local requested=$1
    case $requested in
        up|down|left|right) ;;
        *) return 1 ;;
    esac

    case "$next_direction:$requested" in
        up:down|down:up|left:right|right:left) return 0 ;;
    esac
    next_direction=$requested
}

read_input() {
    local key rest
    key=
    if ! IFS= read -r -s -n 1 -t "$1" key; then
        return 0
    fi

    case $key in
        w|W) set_direction up ;;
        s|S) set_direction down ;;
        a|A) set_direction left ;;
        d|D) set_direction right ;;
        q|Q) game_over_reason="You quit." ;;
        $'\e')
            rest=
            if IFS= read -r -s -n 2 -t 0.01 rest; then
                case $rest in
                    '[A') set_direction up ;;
                    '[B') set_direction down ;;
                    '[C') set_direction right ;;
                    '[D') set_direction left ;;
                esac
            fi
            ;;
    esac
}

advance_game() {
    local head_x=${snake_x[${#snake_x[@]}-1]}
    local head_y=${snake_y[${#snake_y[@]}-1]}
    local new_x=$head_x new_y=$head_y index
    direction=$next_direction

    case $direction in
        up) ((new_y--)) ;;
        down) ((new_y++)) ;;
        left) ((new_x--)) ;;
        right) ((new_x++)) ;;
    esac

    if ((new_x < 0 || new_x >= WIDTH || new_y < 0 || new_y >= HEIGHT)); then
        game_over_reason="You hit the wall."
        return 1
    fi

    local ate_food=0
    ((new_x == food_x && new_y == food_y)) && ate_food=1
    local body_start=0 body_end=${#snake_x[@]}
    if ((ate_food == 0)); then
        ((body_end--))
        body_start=1
    fi
    for ((index = body_start; index < body_end; index++)); do
        if ((snake_x[index] == new_x && snake_y[index] == new_y)); then
            game_over_reason="You ran into yourself."
            return 1
        fi
    done

    snake_x+=("$new_x")
    snake_y+=("$new_y")
    if ((ate_food)); then
        ((score++))
        place_food || game_over_reason="You filled the board!"
    else
        snake_x=("${snake_x[@]:1}")
        snake_y=("${snake_y[@]:1}")
    fi
    return 0
}

render() {
    local row col index glyph cell_color
    printf '\033[H'
    printf '%sSNAKE   Score: %-5d   Length: %-3d   Controls: arrows/WASD, Q quits%s\n' "$COLOR_TEXT" "$score" "${#snake_x[@]}" "$COLOR_RESET"
    printf '%s+' "$COLOR_BORDER"
    for ((col = 0; col < WIDTH; col++)); do printf -- '-'; done
    printf '+%s\n' "$COLOR_RESET"

    for ((row = 0; row < HEIGHT; row++)); do
        printf '%s|%s' "$COLOR_BORDER" "$COLOR_RESET"
        for ((col = 0; col < WIDTH; col++)); do
            glyph=' '
            cell_color=
            if ((col == food_x && row == food_y)); then
                glyph='*'
                cell_color=$COLOR_FOOD
            fi
            for index in "${!snake_x[@]}"; do
                if ((snake_x[index] == col && snake_y[index] == row)); then
                    glyph='o'
                    cell_color=$COLOR_SNAKE
                    if ((index == ${#snake_x[@]} - 1)); then
                        glyph='@'
                        cell_color=$COLOR_HEAD
                    fi
                    break
                fi
            done
            if [[ -n $cell_color ]]; then
                printf '%s%s%s' "$cell_color" "$glyph" "$COLOR_RESET"
            else
                printf '%s' "$glyph"
            fi
        done
        printf '%s|%s\n' "$COLOR_BORDER" "$COLOR_RESET"
    done

    printf '%s+' "$COLOR_BORDER"
    for ((col = 0; col < WIDTH; col++)); do printf -- '-'; done
    printf '+%s\n' "$COLOR_RESET"
}

cleanup_terminal() {
    if [[ -n $old_stty ]]; then
        stty "$old_stty" 2>/dev/null || true
        old_stty=
        printf '\033[?25h\033[0m\n'
    fi
}

handle_signal() {
    local exit_status=$1
    trap - INT TERM
    exit "$exit_status"
}

check_terminal_size() {
    local columns lines
    columns=$(tput cols 2>/dev/null) || columns=0
    lines=$(tput lines 2>/dev/null) || lines=0
    ((columns >= WIDTH + 2 && lines >= HEIGHT + 4)) || fail "terminal is too small (need at least $((WIDTH + 2))x$((HEIGHT + 4)))"
}

play_game() {
    [[ -t 0 && -t 1 ]] || fail "an interactive terminal is required to play"
    check_terminal_size
    old_stty=$(stty -g) || fail "could not read terminal settings"
    trap cleanup_terminal EXIT
    trap 'handle_signal 130' INT
    trap 'handle_signal 143' TERM
    stty -echo -icanon min 0 time 0 || fail "could not configure terminal input"
    printf '\033[2J\033[H\033[?25l'

    reset_game
    local delay
    delay=$(awk -v speed="$SPEED" 'BEGIN { printf "%.4f", 1 / speed }')
    render
    while [[ -z $game_over_reason ]]; do
        read_input 0.01
        [[ -n $game_over_reason ]] && break
        sleep "$delay"
        [[ -n $game_over_reason ]] && break
        advance_game
        render
    done

    printf '\nGame over: %s  Final score: %d\n' "$game_over_reason" "$score"
    printf 'Press Enter to exit.\n'
    IFS= read -r -s -n 1
}

assert_equal() {
    local expected=$1 actual=$2 message=$3
    if [[ $expected != "$actual" ]]; then
        printf 'FAIL: %s (expected %s, got %s)\n' "$message" "$expected" "$actual" >&2
        return 1
    fi
}

assert_contains() {
    local haystack=$1 needle=$2 message=$3
    if [[ $haystack != *"$needle"* ]]; then
        printf 'FAIL: %s (missing %s)\n' "$message" "$needle" >&2
        return 1
    fi
}

run_tests() {
    local failures=0 rendered invalid_option_status
    assert_equal 31 "$(decimal_value 031)" 'leading-zero values use decimal parsing' || ((failures++))
    assert_equal 30 "$(decimal_value 030)" 'decimal conversion preserves speed values' || ((failures++))

    bash "$0" -x >/dev/null 2>&1
    invalid_option_status=$?
    assert_equal 2 "$invalid_option_status" 'unknown short options are rejected' || ((failures++))

    WIDTH=12
    HEIGHT=8
    snake_x=(2 3 4)
    snake_y=(3 3 3)
    assert_equal 0 "$(cell_is_snake 2 3; echo $?)" 'snake cell is detected' || ((failures++))
    assert_equal 1 "$(cell_is_snake 8 3; echo $?)" 'empty cell is detected' || ((failures++))

    direction=right
    next_direction=right
    set_direction up
    assert_equal up "$next_direction" 'valid direction is accepted' || ((failures++))
    set_direction down
    assert_equal up "$next_direction" 'reverse direction is rejected' || ((failures++))

    direction=up
    next_direction=up
    game_over_reason=
    read_input 0.01 <<< d
    assert_equal right "$next_direction" 'buffered movement input is consumed' || ((failures++))
    read_input 0.01 <<< q
    assert_equal 'You quit.' "$game_over_reason" 'buffered quit input is consumed' || ((failures++))

    snake_x=(2 2 3 3)
    snake_y=(2 3 3 2)
    direction=left
    next_direction=left
    food_x=10
    food_y=7
    game_over_reason=
    advance_game
    assert_equal '' "$game_over_reason" 'moving into the departing tail is allowed' || ((failures++))
    assert_equal 3 "${snake_y[0]}" 'tail-entry turn removes the old tail' || ((failures++))
    assert_equal 2 "${snake_x[3]}" 'tail-entry turn moves the head' || ((failures++))

    snake_x=(4 5 6)
    snake_y=(3 3 3)
    direction=right
    next_direction=right
    food_x=10
    food_y=7
    game_over_reason=
    advance_game
    assert_equal 5 "${snake_x[0]}" 'tail advances after movement' || ((failures++))
    assert_equal 7 "${snake_x[2]}" 'head advances after movement' || ((failures++))

    snake_x=(4 5 6)
    snake_y=(3 3 3)
    direction=right
    next_direction=right
    food_x=7
    food_y=3
    score=0
    game_over_reason=
    advance_game
    assert_equal 4 "${#snake_x[@]}" 'eating food grows the snake' || ((failures++))
    assert_equal 1 "$score" 'eating food increases score' || ((failures++))

    snake_x=(1 1 2)
    snake_y=(1 2 2)
    direction=left
    next_direction=left
    food_x=10
    food_y=7
    game_over_reason=
    advance_game
    assert_equal 'You ran into yourself.' "$game_over_reason" 'self collision ends game' || ((failures++))

    snake_x=(9 10 11)
    snake_y=(0 0 0)
    direction=right
    next_direction=right
    food_x=4
    food_y=7
    game_over_reason=
    advance_game
    assert_equal 'You hit the wall.' "$game_over_reason" 'wall collision ends game' || ((failures++))

    snake_x=(4 5 6)
    snake_y=(3 3 3)
    food_x=9
    food_y=6
    score=2
    rendered=$(render)
    assert_contains "$rendered" "$COLOR_TEXT" 'render colors the status text' || ((failures++))
    assert_contains "$rendered" "$COLOR_BORDER" 'render colors the board border' || ((failures++))
    assert_contains "$rendered" "$COLOR_SNAKE" 'render colors the snake body' || ((failures++))
    assert_contains "$rendered" "$COLOR_HEAD" 'render colors the snake head' || ((failures++))
    assert_contains "$rendered" "$COLOR_FOOD" 'render colors the food' || ((failures++))
    assert_contains "$rendered" "$COLOR_RESET" 'render resets colors' || ((failures++))

    if ((failures)); then
        printf '%d test(s) failed.\n' "$failures" >&2
        return 1
    fi
    printf 'All snake tests passed.\n'
}

main() {
    parse_options "$@"
    [[ -n $SEED ]] && RANDOM=$SEED
    play_game
}

main "$@"
