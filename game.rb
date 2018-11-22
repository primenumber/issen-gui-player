X = 50
Y = 50
WIDTH = 640
HEIGHT = 640
WINDOW_WIDTH = 2*X + WIDTH
WINDOW_HIEGHT = 2*Y + HEIGHT
CX = WINDOW_WIDTH / 2
CY = WINDOW_HIEGHT / 2
window_size(WINDOW_WIDTH, WINDOW_HIEGHT)
set_title("Othello")

class Board
  EMPTY = 0
  BLACK = 1
  WHITE = 2
  def initialize
    @data = Array.new(8).map{Array.new(8, EMPTY)}
    @data[3][3] = WHITE
    @data[3][4] = BLACK
    @data[4][3] = BLACK
    @data[4][4] = WHITE
    @turn = BLACK
    @passed_prev = false
  end
  def at(i, j)
    @data[i][j]
  end
  def turn
    @turn
  end
  def movable_any?
    8.times do |i|
      8.times do |j|
        return true if movable?(i, j)
      end
    end
    return false
  end
  def movable?(i, j)
    return false if i < 0 || i >= 8 || j < 0 || j >= 8
    return false unless @data[i][j] == EMPTY
    8.times do |k|
      return true if movable_dir?(i, j, k)
    end
    false
  end
  def move(i, j)
    false unless movable?(i, j)
    8.times do |k|
      move_dir(i, j, k)
    end
    @data[i][j] = @turn
    play
    @passed_prev = false
    true
  end
  def pass
    return false if movable_any?
    play
    @passed_prev = true
    true
  end
  def gameover?
    @passed_prev && !movable_any?
  end
  def to_s
    res = ""
    8.times do |i|
      8.times do |j|
        case @data[i][j]
        when EMPTY then
          res += ?-
        when BLACK then
          res += ?X
        when WHITE then
          res += ?O
        end
      end
    end
    res
  end
  def turn_s
    if @turn == BLACK
      "Black"
    else
      "White"
    end
  end
  def count
    b = 0
    w = 0
    8.times do |i|
      8.times do |j|
        if @data[i][j] == BLACK
          b += 1
        elsif @data[i][j] == WHITE
          w += 1
        end
      end
    end
    if b < w then
      [b, 64-b]
    elsif b > w then
      [64-w, w]
    else
      [32, 32]
    end
  end

  private

  def movable_dir?(i, j, k)
    di = [1, 1, 1, 0, -1, -1, -1, 0]
    dj = [1, 0, -1, -1, -1, 0, 1, 1]
    (1..8).each do |n|
      ni = i + di[k] * n
      nj = j + dj[k] * n
      return false if ni < 0 || ni >= 8 || nj < 0 || nj >= 8
      return false if @data[ni][nj] == EMPTY
      if @data[ni][nj] == @turn then
        return n > 1 # opponent stone continue >0 times
      end
    end
    false # never come
  end
  def move_dir(i, j, k)
    di = [1, 1, 1, 0, -1, -1, -1, 0]
    dj = [1, 0, -1, -1, -1, 0, 1, 1]
    (1..8).each do |n|
      ni = i + di[k] * n
      nj = j + dj[k] * n
      return if ni < 0 || ni >= 8 || nj < 0 || nj >= 8
      return if @data[ni][nj] == EMPTY
      if @data[ni][nj] == @turn then
        (1...n).each do |m|
          mi = i + di[k] * m
          mj = j + dj[k] * m
          @data[mi][mj] = @turn
        end
        break
      end
    end
  end
  def play
    if @turn == BLACK then
      @turn = WHITE
    else
      @turn = BLACK
    end
  end
end

def draw_disc(x, y, color)
  case color
  when Board::BLACK then
    put_image("black.png", x: x, y: y, colorkey: false)
  when Board::WHITE then
    put_image("white.png", x: x, y: y, colorkey: false)
  end
end

def draw_board(board)
  fill_rect(X, Y, WIDTH, HEIGHT, [0, 127, 0])
  w = WIDTH / 8
  h = HEIGHT / 8
  8.times do |i|
    8.times do |j|
      if board.at(i, j) == Board::EMPTY then
        if board.movable?(i, j) then
          fill_rect(X + w*j, Y + h*i, w, h, [127, 127, 0])
        end
      else
        draw_disc(X + w*j, Y + h*i, board.at(i, j))
      end
    end
  end
  (1..7).each do |i|
    draw_line(X + w*i, Y, X + w*i, Y + HEIGHT, BLACK)
    draw_line(X, Y + h*i, X + WIDTH, Y + h*i, BLACK)
  end
  draw_rect(X, Y, WIDTH, HEIGHT, WHITE)
end

def create_pipe
  IO.pipe.map{|pipe| pipe.tap{|_| _.set_encoding("ASCII-8BIT", "ASCII-8BIT") } }
end

$board = Board.new()

$think_process = nil
$think_thread = nil
$thinking = false
$parent_read, $child_write = create_pipe
$level = 1
$selecting = true

def alive?(pid)
  Process.kill(0, pid)
  true
rescue Errno::ESRCH
  false
end

def launch
  $think_process = Process.fork do
    $parent_read.close
    res = `../think.sh #{$board} #{$board.turn_s} #{$level}`
    $child_write.write res
    loop do
      sleep 1
    end
  end
  $think_thread = Thread.new do
    $thinking = true
    result = $parent_read.gets
    if alive?($think_process) then
      Process.kill("KILL", $think_process)
      Process.wait($think_process)
    end
    result
  end
end

def parse_pos(str)
  [str[1].ord - ?1.ord, str[0].ord - ?a.ord]
end

def draw_select_level
  fill_rect(CX - 250, CY - 100, 500, 200, WHITE)
  text("レベルを選んでください", x: CX - 180, y: CY - 80, color: BLACK)
  fill_rect(CX - 200, CY, 150, 50, BLACK)
  text("Level1", x: CX - 180, y: CY + 10, color: WHITE)
  fill_rect(CX + 50, CY, 150, 50, BLACK)
  text("Level0", x: CX + 70, y: CY + 10, color: WHITE)
end

def hit1?(x, y)
  x >= CX - 200 && y >= CY && x <= CX - 50 && y <= CY + 50
end

def hit0?(x, y)
  x >= CX + 50 && y >= CY && x <= CX + 200 && y <= CY + 50
end

mainloop do
  clear_window
  draw_board($board)
  if $selecting then
    if mousebutton_click?(1) then
      if hit1?(mouse_x, mouse_y) then
        $selecting = false
        $level = 1
      elsif hit0?(mouse_x, mouse_y) then
        $selecting = false
        $level = 0
      else
        draw_select_level
      end
    else
      draw_select_level
    end
  elsif $thinking then
    if $think_thread != nil && !$think_thread.alive? then
      $thinking = false
      pos = $think_thread.value
      p pos
      if pos == "ps" then
        $board.pass
      else
        i, j = parse_pos(pos)
        $board.move(i, j)
      end
    else
      fill_rect(CX - 200, CY - 50, 400, 100, WHITE)
      text("考え中...", x: CX - 150, y: CY - 30, color: BLACK)
    end
  elsif mousebutton_click?(1) then
    if $board.gameover?
      $board = Board.new()
      $selecting = true
    else
      w = WIDTH / 8
      h = HEIGHT / 8
      j = (mouse_x - X) / w
      i = (mouse_y - Y) / h
      if $board.movable?(i, j) then
        $board.move(i, j)
        if $board.movable_any? then
          launch
        else
          $board.pass
        end
      elsif !$board.movable_any? then
        $board.pass
        if $board.movable_any? then
          launch
        elsif !$board.gameover? then
          $board.pass
        end
      end
    end
  elsif $board.gameover? then
    fill_rect(CX - 200, CY - 50, 400, 100, WHITE)
    b, w = $board.count
    text("ゲーム終了 #{b} vs #{w}", x: CX - 150, y: CY - 30, color: BLACK)
  elsif !$board.movable_any? then
    fill_rect(CX - 200, CY - 50, 400, 100, WHITE)
    text("パスです", x: CX - 150, y: CY - 30, color: BLACK)
  end
end

