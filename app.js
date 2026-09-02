const canvas = document.querySelector('#game-canvas');
const context = canvas.getContext('2d');
const scoreElement = document.querySelector('#score');
const highScoreElement = document.querySelector('#high-score');
const statusElement = document.querySelector('#status');
const statusLabel = document.querySelector('#status-label');
const gameMessage = document.querySelector('#game-message');
const messageKicker = gameMessage.querySelector('.message-kicker');
const messageBody = gameMessage.querySelector('strong');
const messageHint = gameMessage.querySelector('.message-hint');
const pauseButton = document.querySelector('#pause-button');
const pauseLabel = document.querySelector('#pause-label');
const boardSize = 20;
const tickLength = 128;

const directions = {
  up: { x: 0, y: -1 },
  down: { x: 0, y: 1 },
  left: { x: -1, y: 0 },
  right: { x: 1, y: 0 },
};

let snake;
let food;
let direction;
let queuedDirection;
let score;
let highScore = Number(localStorage.getItem('snake-high-score') || 0);
let gameState = 'ready';
let lastFrame = 0;
let elapsed = 0;
let foodPulse = 0;
let touchStart = null;

function formatScore(value) {
  return String(value).padStart(3, '0');
}

function setStatus(state, label) {
  gameState = state;
  statusElement.dataset.state = state;
  statusLabel.textContent = label;
}

function showMessage(kicker, body, hint) {
  messageKicker.textContent = kicker;
  messageBody.innerHTML = body;
  messageHint.textContent = hint;
  gameMessage.classList.remove('is-hidden');
}

function hideMessage() {
  gameMessage.classList.add('is-hidden');
}

function updateScore() {
  scoreElement.textContent = formatScore(score);
  highScoreElement.textContent = formatScore(highScore);
}

function randomFood() {
  const openCells = [];
  for (let y = 0; y < boardSize; y += 1) {
    for (let x = 0; x < boardSize; x += 1) {
      if (!snake.some((segment) => segment.x === x && segment.y === y)) {
        openCells.push({ x, y });
      }
    }
  }
  return openCells[Math.floor(Math.random() * openCells.length)] || null;
}

function resetGame() {
  snake = [
    { x: 10, y: 10 },
    { x: 9, y: 10 },
    { x: 8, y: 10 },
  ];
  direction = 'right';
  queuedDirection = 'right';
  score = 0;
  food = randomFood();
  elapsed = 0;
  pauseLabel.textContent = 'Pause';
  pauseButton.setAttribute('aria-label', 'Pause game');
  setStatus('ready', 'Ready');
  showMessage('Ready when you are', 'Press a direction<br>to start', 'or tap the pad below');
  updateScore();
  draw();
}

function startGame() {
  if (gameState === 'ready') {
    setStatus('playing', 'Running');
    hideMessage();
  }
}

function changeDirection(nextDirection) {
  const next = directions[nextDirection];
  if (!next) return;
  if (gameState === 'over') return;
  if (gameState === 'paused') return;

  const current = directions[direction];
  if (next.x === -current.x && next.y === -current.y) return;
  queuedDirection = nextDirection;
  startGame();
}

function step() {
  direction = queuedDirection;
  const vector = directions[direction];
  const head = snake[0];
  const nextHead = { x: head.x + vector.x, y: head.y + vector.y };
  const eating = nextHead.x === food?.x && nextHead.y === food?.y;
  const bodyToCheck = eating ? snake : snake.slice(0, -1);
  const hitWall = nextHead.x < 0 || nextHead.x >= boardSize || nextHead.y < 0 || nextHead.y >= boardSize;
  const hitSelf = bodyToCheck.some((segment) => segment.x === nextHead.x && segment.y === nextHead.y);

  if (hitWall || hitSelf) {
    endGame();
    return;
  }

  snake.unshift(nextHead);
  if (eating) {
    score += 1;
    if (score > highScore) {
      highScore = score;
      localStorage.setItem('snake-high-score', String(highScore));
    }
    food = randomFood();
    updateScore();
    if (!food) {
      endGame(true);
      return;
    }
  } else {
    snake.pop();
  }
}

function endGame(boardComplete = false) {
  setStatus('over', 'Game over');
  pauseLabel.textContent = 'Pause';
  pauseButton.setAttribute('aria-label', 'Pause game');
  showMessage(
    boardComplete ? 'Perfect run' : 'Run complete',
    boardComplete ? 'You filled<br>the whole board' : 'Nice try.<br>Go again?',
    boardComplete ? 'every square is yours' : 'press New game to reset',
  );
  draw();
}

function togglePause() {
  if (gameState === 'over') return;
  if (gameState === 'ready') {
    startGame();
    return;
  }
  if (gameState === 'paused') {
    setStatus('playing', 'Running');
    hideMessage();
    pauseLabel.textContent = 'Pause';
    pauseButton.setAttribute('aria-label', 'Pause game');
  } else {
    setStatus('paused', 'Paused');
    showMessage('Taking five', 'Game<br>paused', 'press Pause to continue');
    pauseLabel.textContent = 'Resume';
    pauseButton.setAttribute('aria-label', 'Resume game');
  }
}

function roundedRect(x, y, width, height, radius) {
  const safeRadius = Math.min(radius, width / 2, height / 2);
  context.beginPath();
  context.roundRect(x, y, width, height, safeRadius);
}

function drawGrid(cellSize) {
  context.fillStyle = '#172126';
  context.fillRect(0, 0, canvas.width, canvas.height);
  context.strokeStyle = 'rgba(240, 236, 225, 0.055)';
  context.lineWidth = 1;
  for (let line = 1; line < boardSize; line += 1) {
    const position = line * cellSize + 0.5;
    context.beginPath();
    context.moveTo(position, 0);
    context.lineTo(position, canvas.height);
    context.moveTo(0, position);
    context.lineTo(canvas.width, position);
    context.stroke();
  }
  context.strokeStyle = 'rgba(213, 238, 81, 0.18)';
  context.strokeRect(0.5, 0.5, canvas.width - 1, canvas.height - 1);
}

function drawFood(cellSize) {
  if (!food) return;
  const centerX = food.x * cellSize + cellSize / 2;
  const centerY = food.y * cellSize + cellSize / 2;
  const pulse = 1 + Math.sin(foodPulse) * 0.08;
  const radius = cellSize * 0.19 * pulse;

  context.save();
  context.translate(centerX, centerY);
  context.rotate(Math.PI / 4);
  context.shadowColor = 'rgba(255, 121, 92, .72)';
  context.shadowBlur = 16;
  context.fillStyle = '#ff795c';
  roundedRect(-radius, -radius, radius * 2, radius * 2, radius * .28);
  context.fill();
  context.shadowBlur = 0;
  context.fillStyle = '#ffb09d';
  roundedRect(-radius * .34, -radius * .34, radius * .45, radius * .45, radius * .1);
  context.fill();
  context.restore();
}

function drawSnake(cellSize) {
  snake.forEach((segment, index) => {
    const inset = index === 0 ? cellSize * .12 : cellSize * .18;
    const x = segment.x * cellSize + inset;
    const y = segment.y * cellSize + inset;
    const size = cellSize - inset * 2;
    const isHead = index === 0;

    context.fillStyle = isHead ? '#eafa73' : `rgba(213, 238, 81, ${Math.max(.38, 1 - index / (snake.length * 1.3))})`;
    context.shadowColor = isHead ? 'rgba(213, 238, 81, .4)' : 'transparent';
    context.shadowBlur = isHead ? 15 : 0;
    roundedRect(x, y, size, size, cellSize * .22);
    context.fill();
    context.shadowBlur = 0;

    if (isHead) {
      const eyeSize = Math.max(2.5, cellSize * .07);
      const eyeOffset = cellSize * .28;
      context.fillStyle = '#172126';
      if (direction === 'left' || direction === 'right') {
        const eyeX = direction === 'right' ? x + size - eyeOffset : x + eyeOffset;
        context.beginPath();
        context.arc(eyeX, y + size * .3, eyeSize, 0, Math.PI * 2);
        context.arc(eyeX, y + size * .7, eyeSize, 0, Math.PI * 2);
      } else {
        const eyeY = direction === 'down' ? y + size - eyeOffset : y + eyeOffset;
        context.beginPath();
        context.arc(x + size * .3, eyeY, eyeSize, 0, Math.PI * 2);
        context.arc(x + size * .7, eyeY, eyeSize, 0, Math.PI * 2);
      }
      context.fill();
    }
  });
}

function draw() {
  const cellSize = canvas.width / boardSize;
  drawGrid(cellSize);
  drawFood(cellSize);
  drawSnake(cellSize);
}

function frame(timestamp) {
  if (!lastFrame) lastFrame = timestamp;
  const delta = Math.min(timestamp - lastFrame, 100);
  lastFrame = timestamp;
  foodPulse += delta * .006;

  if (gameState === 'playing') {
    elapsed += delta;
    while (elapsed >= tickLength) {
      step();
      elapsed -= tickLength;
      if (gameState !== 'playing') break;
    }
  }

  draw();
  requestAnimationFrame(frame);
}

function handleKeydown(event) {
  const keyDirections = {
    ArrowUp: 'up',
    ArrowDown: 'down',
    ArrowLeft: 'left',
    ArrowRight: 'right',
    w: 'up',
    W: 'up',
    s: 'down',
    S: 'down',
    a: 'left',
    A: 'left',
    d: 'right',
    D: 'right',
  };
  if (keyDirections[event.key]) {
    event.preventDefault();
    changeDirection(keyDirections[event.key]);
  } else if (event.key === ' ' || event.key === 'p' || event.key === 'P') {
    event.preventDefault();
    togglePause();
  } else if (event.key === 'Enter' && gameState === 'over') {
    resetGame();
  }
}

function handleTouchStart(event) {
  const [touch] = event.touches;
  touchStart = { x: touch.clientX, y: touch.clientY };
}

function handleTouchEnd(event) {
  if (!touchStart) return;
  const [touch] = event.changedTouches;
  const deltaX = touch.clientX - touchStart.x;
  const deltaY = touch.clientY - touchStart.y;
  touchStart = null;
  if (Math.max(Math.abs(deltaX), Math.abs(deltaY)) < 24) return;
  if (Math.abs(deltaX) > Math.abs(deltaY)) {
    changeDirection(deltaX > 0 ? 'right' : 'left');
  } else {
    changeDirection(deltaY > 0 ? 'down' : 'up');
  }
}

document.addEventListener('keydown', handleKeydown);
pauseButton.addEventListener('click', togglePause);
document.querySelector('#new-game-button').addEventListener('click', resetGame);
document.querySelectorAll('[data-direction]').forEach((button) => {
  button.addEventListener('click', () => changeDirection(button.dataset.direction));
});
canvas.addEventListener('touchstart', handleTouchStart, { passive: true });
canvas.addEventListener('touchend', handleTouchEnd, { passive: true });

highScoreElement.textContent = formatScore(highScore);
resetGame();
requestAnimationFrame(frame);
