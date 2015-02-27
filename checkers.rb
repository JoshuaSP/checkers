require 'matrix'
require 'byebug'
require 'colorize'
# require 'curses'

class Piece
  attr_accessor :king, :pos
  attr_reader :color, :board

  def initialize(board, pos, color, king = false)
    @board, @pos, @color, @king = board, Vector[*pos], color, king
  end

  def symbol
    (king ? "♛" : "❂").colorize(:color => color)
  end

  def dirs
    ([[1,-1], [1,1]] + (king ? [[-1,1], [-1,-1]] : [])).map do |dir|
      if color == :black
        Vector[*dir]
      else
        Vector[-dir[0], dir[1]]
      end
    end
  end

  def jump_possible?(dir)
    board[pos + dir] && board[pos + dir].color != self.color && board[pos + 2 * dir].nil?
  end

  def poss_jumps
    dirs.select do |dir|
      jump_possible?(dir)
    end.map do |dir|
      pos + 2 * dir
    end
  end

  def poss_slides
    dirs.map do |dir|
      pos + dir
    end.select do |move|
      board[move].nil?
    end
  end

  def poss_moves
    poss_jumps + poss_slides
  end
end

class Board
  attr_reader :squares, :size, :num_pieces
  attr_accessor :cursor, :lasterror

  COLORS ||= [:black, :white]

  def initialize(size = 8, num_pieces = nil)
    @size = size
    @num_pieces = num_pieces
    @squares = Array.new(8) { Array.new(8) }
    fill_board if num_pieces
    @cursor = Vector[0,0]
  end

  def fill_board
    rows = num_pieces / (size / 2)
    colors.each do |color|
      (0...rows).each do |row|
        (0...size/2).each do |pos|
          black_pos = [row, 2 * pos + row % 2]
          white_pos = [size - row - 1, 2 * pos + (row + 1) % 2]
          my_pos = color == :black ? black_pos : white_pos
          self[my_pos] = Piece.new(self, my_pos, color)
        end
      end
    end
  end

  def [](pos1, pos2 = nil)
    if pos2.nil?
      pos2 = pos1[1]
      pos1 = pos1[0]
    end
    if [pos1, pos2].all? { |coordinate| (0...size).cover?(coordinate) }
      @squares[pos1][pos2]
    else
      false
    end
  end

  def []=(pos1, pos2_or_value, value = nil)
    if pos1.is_a?(Vector) || pos1.is_a?(Array)
      @squares[pos1[0]][pos1[1]] = pos2_or_value
    else
      @squares[pos1, pos2_or_value] = value
    end
  end

  def pieces
    pieces = []
    (0...size).each do |row|
      (0...size).each do |pos|
        current_piece = self[row, pos]
        pieces << current_piece if current_piece
      end
    end
    pieces
  end

  def colors
    COLORS
  end

  def render(current_player = nil)
    system('clear')

    puts " ~~~~~~~~~~~~~~~~~~~~~~~~~~~ ".colorize(:green)
    puts " move cursor to select piece ".colorize(:green)
    puts "   press spacebar to select ".colorize(:green)
    puts "      piece and target".colorize(:green)
    puts "       press q to quit ".colorize(:green)
    puts " ~~~~~~~~~~~~~~~~~~~~~~~~~~~ ".colorize(:green)
    puts
    (0...size).each do |row|
      print "      "
      (0...size).each do |pos|
        boardcolor = [:red, :magenta][(pos + row) % 2]
        boardcolor = :light_blue if @cursor == Vector[row, pos]
        char = (self[row, pos] ? self[row, pos].symbol + " " : "  ")
        print char.colorize(:background => boardcolor)
      end
      print "\n"
    end
    puts
    puts current_player.color.to_s + " to move.".colorize(:green) if current_player
    puts @lasterror.colorize(:red) if @lasterror
  end
end

class Game
  attr_accessor :board, :turns, :current_player
  attr_reader :players, :size, :pieces

  def initialize(player1 = HumanPlayer.new(:black),
                player2 = HumanPlayer.new(:white),
                size = 8,
                pieces = 12)
    @players = [player1, player2]
    @size, @pieces = size, pieces
    @board = Board.new(size, pieces)
    @turns = 0
    @current_player = player1
  end

  def play
    until won?
      # board.render(@current_player)
      self.current_player = players[turns % 2]
      move(current_player)
      self.turns += 1
    end
    board.render(nil)
    puts board.pieces[0].color.to_s.capitalize + " won!!!"
  end

  def won?
    board.pieces.map { |piece| piece.color }.uniq.length == 1
  end

  def move(player)
    begin
      move_type = make_move(player.get_move(board))
      board.lasterror = nil
    rescue RuntimeError => err
      board.lasterror = err.message
      retry
    end
    if move_type == :jump
      until no_jumps_available
        begin
          make_jump_move(player.get_move(board, 1))
        rescue RuntimeError => err
          board.lasterror = err.message
          retry
        end
        board.lasterror = nil
      end
    end
    king_me_if_possible
  end

  def king_me_if_possible
    @current_piece.king = true if @current_piece.pos[0] == final_row
  end

  def final_row
    turns % 2 == 0 ? size : 0
  end

  def no_jumps_available
    @current_piece.poss_jumps.empty? || @current_piece.pos[0] == final_row
  end

  def make_move(positions)
    @current_piece = board[positions[0]]
    raise "no piece there!" if board[positions[0]].nil?
    my_pieces = board.pieces.select { |piece| piece.color == @current_player.color}
    no_jumps = my_pieces.map { |piece| piece.poss_jumps }.inject(:+).empty?
    currently_jumping = @current_piece.poss_jumps.include?(positions[1])
    raise "not your piece" if @current_piece.color != @current_player.color
    raise "not a valid move" unless @current_piece.poss_moves.include?(positions[1])
    raise "you must jump if you can" unless no_jumps || currently_jumping
    if currently_jumping
      taken_piece = (positions[1] - positions[0]) / 2 + positions[0]
      board[taken_piece] = nil
    end
    board[positions[1]] = @current_piece
    board[positions[0]] = nil
    @current_piece.pos = positions[1]
    currently_jumping ? :jump : :slide
  end

  def make_jump_move(position)
    position = position[0]
    raise "not a valid move" unless @current_piece.poss_jumps.include?(position)
    taken_piece = (position - @current_piece.pos) / 2 + @current_piece.pos
    board[taken_piece] = nil
    board[@current_piece.pos] = nil
    board[position] = @current_piece
    @current_piece.pos = position
  end
end

class HumanPlayer
  attr_accessor :color

  def initialize(color = :white)
    @color = color
  end

  def get_move(board, inputs = 2)
    positions = []
    until positions.length == inputs
      board.render(self)
      c = read_char
      orig_pos = board.cursor
      case c
      when " "
        positions << board.cursor
      when "\e[A"
        board.cursor += Vector[-1,0]
      when "\e[B"
        board.cursor += Vector[1,0]
      when "\e[C"
        board.cursor += Vector[0,1]
      when "\e[D"
        board.cursor += Vector[0,-1]
      when "q"
        exit 0
      end
      board.cursor = orig_pos if board[board.cursor] == false
    end
    puts positions
    positions
  end

  def read_char
    STDIN.echo = false
    STDIN.raw!

    input = STDIN.getc.chr
    if input == "\e" then
      input << STDIN.read_nonblock(3) rescue nil
      input << STDIN.read_nonblock(2) rescue nil
    end
  ensure
    STDIN.echo = true
    STDIN.cooked!

    return input
  end
end
