# -*- coding: utf-8 -*-
require 'sdl2'
require 'set'

module SDL2::Q
  module_function

  # @api private
  # 初期化
  def init(title)
    SDL2.init(SDL2::INIT_EVERYTHING)
    @@window = SDL2::Window.create(title, 0, 0, 640, 480, 0)
    @@renderer = @@window.create_renderer(-1, 0)
    @@fpskeeper = FPSKeeper.new(30)
    @@title = title
    
    @@textures = Hash.new
    @@cell_definitions = Hash.new
    
    SDL2::TTF.init
    @@fonts = Hash.new
    set_fontsize(32)

    SDL2::Mixer.init(SDL2::Mixer::INIT_OGG|SDL2::Mixer::INIT_MP3)
    SDL2::Mixer.open(44100)
    @@musics = Hash.new
    
    clear_window
  end

  FONT_PATH = File.join(__dir__, "VL-Gothic-Regular.ttf")
  private_constant :FONT_PATH
  
  # メインループ。
  #
  # ブロック付きで呼び出すと毎ループごとにそのブロックが呼びだされます。
  def mainloop
    @@fpskeeper.reset
    
    loop do
      @@keydown = Set.new
      while event = SDL2::Event.poll
        case event
        when SDL2::Event::Quit
          exit
        when SDL2::Event::KeyDown
          @@keydown.add(event.sym)
        end
      end
      
      yield if block_given?
      @@fpskeeper.wait_frame { @@renderer.present }
    end
  end

  # @!group Window drawing
  
  # ウィンドウを黒でクリアします。
  def clear_window
    @@renderer.draw_color = BLACK
    @@renderer.clear
  end

  # 画像をウィンドウの (x, y, w, h) の領域に描画します。
  #
  # w, h を省略したときは画像の大きさが使われます。
  #
  # 画像を回転させたときには描画領域にちょうどおさまるように
  # 大きさを調整します。
  #
  # * Q: 背景画像に使いたいので背景が透ける機能(カラーキー)を
  #   無効にしたい
  #   * A: colorkey: false としてください
  # * Q: blend_mode のデフォルト値が "BLEND" なのは何故か
  #   * A: カラーキーの実装に必要なのためです
  # * Q: 機能が多すぎてややこしい
  #   * A: 以下の example を参照してください。おおよそ
  #        適切なデフォルトが設定されています。
  #        教える方は簡単なほうから段階的に必要なものだけ教えてください
  #        
  # @param image [String] 画像のファイル名
  # @param x [Integer] 描画領域の左上X座標
  # @param y [Integer] 描画領域の左上Y座標
  # @param w [Integer] 描画領域の幅
  # @param h [Integer] 描画領域の高さ
  # @param blend_mode [String] "NONE", "BLEND", "ADD","MOD"のいずれか
  # @param alpha [String] アルファ値
  # @param angle [Float] 回転角度(時計回り、単位は度数)
  # @param flip_vertically [Boolean] true で画像を上下反転する
  # @param flip_horizontally [Boolean] true で画像を左右反転する
  # @example
  #
  #    # 基本: ruby.png を (100, 100) に置く
  #    put_image("ruby.png", x: 100, y: 100)
  #    # 加算ブレンド:
  #    put_image("ruby.png", x: 100, y: 100, blend_mode: "ADD")
  #    # 画像にアルファ値 128 を指定してアルファブレンド:
  #    put_image("ruby.png", x: 100, y: 100, alpha: 128)
  #    # 画像を縦横に拡大して描画
  #    put_image("ruby.png", x: 100, y: 100, w: 128, h: 128)
  #    # 上下反転させてさらに回転
  #    put_image("ruby.png", x: 100, y: 100, angle: 60, flip_vertically: true)
  def put_image(image, x: 0, y: 0, w: nil, h: nil, colorkey: true,
                blend_mode: "BLEND", alpha: 255, angle: 0,
                flip_vertically: false, flip_horizontally: false)
    texture = find_texture(image, colorkey)
    w ||= texture.w
    h ||= texture.h
    
    put_from_texture(texture, nil, SDL2::Rect[x, y, w, h],
                     blend_mode, alpha, angle,
                     flip_vertically, flip_horizontally)
  end

  BLENDMODE = {"NONE" => SDL2::BlendMode::NONE,
               "BLEND" => SDL2::BlendMode::BLEND,
               "ADD" => SDL2::BlendMode::ADD,
               "MOD" => SDL2::BlendMode::MOD,}
  private_constant :BLENDMODE

  # セル(一枚の画像を小さい長方形の画像に分割して一枚の画像と
  # 同様に扱えるようにしたもの)を定義します。
  #
  # 定義した cell は {.cell_put} でウインドウに描画できます。
  # 
  # image で指定した画像ファイルを cellwidth x cellheight の
  # 画像に分割して、cell_putで分割された画像を描画することが
  # できます。cell_putでは、ファイル名とセルIDで画像をしていします。
  # セルIDは以下のように付番されます。
  #
  #      |---|---|---|---|-> X
  #      | 0 | 1 | 2 | 3 |
  #      +---+---+---+---+
  #      | 4 | 5 | 6 | 7 |
  #      +---+---+---+---+
  #      | 8 | 9 |10 |11 |
  #      +---+---+---+---+
  #      |
  #      v
  #      Y
  # 画像の幅ががちょうど cellwidth の倍数でない場合には、
  # 画像の右端のあまりの部分が無視されます。
  # 画像の高さとcellheight でも同様に画像の下端が無視されます。
  #
  # @param image [String] 画像ファイル名
  # @param cellwidth [Integer] 各セルの幅
  # @param cellheight [Integer] 各セルの高さ
  def define_cells(image, cellwidth, cellheight)
    texture = find_texture(image, true)
    # TODO: Check redifinition
    @@cell_definitions[image] = CellDefinition.new(texture, cellwidth, cellheight)
  end

  # {.define_cells} で定義したセルをウィンドウに描画します。
  #
  # image で画像のファイル名を、cellid でセルIDを指定します。
  # それ以外の引数の意味は {.put_image} と同じです。
  #
  # @param image [String] 画像のファイル名
  # @param cellid [Integer] セルID
  # @param x [Integer] 描画領域の左上X座標
  # @param y [Integer] 描画領域の左上Y座標
  # @param w [Integer] 描画領域の幅
  # @param h [Integer] 描画領域の高さ
  # @param blend_mode [String] "NONE", "BLEND", "ADD","MOD"のいずれか
  # @param alpha [String] アルファ値
  # @param angle [Float] 回転角度(単位は度数)
  # @param flip_vertically [Boolean] true で画像を上下反転する
  # @param flip_horizontally [Boolean] true で画像を左右反転する
  def put_cell(image, cellid, x: 0, y: 0, w: nil, h: nil, colorkey: true,
               blend_mode: "BLEND", alpha: 255, angle: 0,
               flip_vertically: false, flip_horizontally: false)
    texture = find_texture(image, colorkey)
    cell_definition = @@cell_definitions.fetch(image) {
      raise "Cell of \"#{image}\" is not defined yet "
    }
    rect = cell_definition.get_rect(cellid)
    w ||= rect.w
    h ||= rect.h
    put_from_texture(texture, rect, SDL2::Rect[x, y, w, h],
                     blend_mode, alpha, angle,
                     flip_vertically, flip_horizontally)
  end

  
  private def put_from_texture(texture, srcrect, dstrect,
                               blend_mode, alpha, angle,
                               flip_vertically, flip_horizontally)
    mode = BLENDMODE.fetch(blend_mode) {
      raise 'blend_mode must be one of "NONE", "BLEND", "ADD", or "MOD"'
    }
    texture.blend_mode = mode
    texture.alpha_mod = alpha
    flip = 0
    flip |= SDL2::Renderer::FLIP_VERTICAL if flip_vertically
    flip |= SDL2::Renderer::FLIP_HORIZONTAL if flip_horizontally
    
    @@renderer.copy_ex(texture, srcrect, dstrect, angle, nil, flip)
  end
  
  # 画像がすでに読み込まれていればそのテクスチャを返し、
  # 読み込まれていなければ読み込んでからそのテクスチャを返す
  private def find_texture(image, colorkey)
    key = [image, colorkey]
    if !@@textures.has_key?(key)
      if colorkey
        surface = SDL2::Surface.load(image)
        surface.color_key = surface.pixel(0, 0)
        @@textures[key] = @@renderer.create_texture_from(surface)
        surface.destroy
      else
        @@textures[key] = @@renderer.load_texture(image)
      end
    end
    return @@textures[key]
  end

  # 直線を描画する
  #
  # @param x1 [Integer] 始点のX座標
  # @param y1 [Integer] 始点のY座標
  # @param x2 [Integer] 終点のX座標
  # @param y2 [Integer] 終点のY座標
  # @param color [[Integer, Integer, Integer]] 色
  def draw_line(x1, y1, x2, y2, color)
    @@renderer.draw_color = color
    @@renderer.draw_line(x1, y1, x2, y2)
  end

  # 塗り潰した四角形を描画する
  #
  # @param x [Integer] 四角形の左上のX座標
  # @param y [Integer] 四角形の左上のY座標
  # @param w [Integer] 四角形の横幅
  # @param h [Integer] 四角形の高さ
  # @param color [[Integer, Integer, Integer]] 色
  def fill_rect(x, y, w, h, color)
    @@renderer.draw_color = color
    @@renderer.fill_rect(SDL2::Rect[x, y, w, h])
  end

  # 四角形を描画する
  #
  # @param x [Integer] 四角形の左上のX座標
  # @param y [Integer] 四角形の左上のY座標
  # @param w [Integer] 四角形の横幅
  # @param h [Integer] 四角形の高さ
  # @param color [[Integer, Integer, Integer]] 色
  def draw_rect(x, y, w, h, color)
    @@renderer.draw_color = color
    @@renderer.draw_rect(SDL2::Rect[x, y, w, h])
  end

  # 点を描画する
  #
  # @param x [Integer] X座標
  # @param y [Integer] Y座標
  # @param color [[Integer, Integer, Integer]] 色
  def draw_point(x, y, color)
    @@renderer.draw_color = color
    @@renderer.draw_point(x, y)
  end

  # 円を描画する
  #
  # @param x [Integer] 中心のX座標
  # @param y [Integer] 中心のY座標
  # @param radius [Integer] 半径
  # @param color [[Integer, Integer, Integer]] 色
  def draw_circle(x, y, radius, color)
    @@renderer.draw_color = color
    64.times do |i|
      @@renderer.draw_line(x + radius*Math.cos(Math::PI/32*i),
                           y + radius*Math.sin(Math::PI/32*i),
                           x + radius*Math.cos(Math::PI/32*(i-1)),
                           y + radius*Math.sin(Math::PI/32*(i-1)))
    end
    @@renderer.draw_point(x, y)
  end

  # 文字列をウィンドウの (x, y) の位置に描画します。
  #
  # @param str [String] 描画する文字列
  # @param x [Integer] 描画文字列の左上X座標
  # @param y [Integer] 描画文字列の左上Y座標
  # @param color [Array<Integer>] 描画色
  def text(str, x: 0, y: 0, color: WHITE)
    surface = @@font.render_solid(str, color)
    texture = @@renderer.create_texture_from(surface)
    @@renderer.copy(texture, nil,
                    SDL2::Rect.new(x, y, texture.w, texture.h)) 
  end

  # {.text} で用いるフォントのサイズを変更します。
  #
  # @param size [Integer] サイズ
  # @return [void]
  def set_fontsize(size)
    @@font = @@fonts.fetch(size) {
      @@fonts[size] = SDL2::TTF.open(FONT_PATH, size)
    }
  end

  WHITE = [255, 255, 255]
  BLACK = [0, 0, 0]
  RED = [255, 0, 0]
  GREEN = [0, 255, 0]
  BLUE = [0, 0, 255]
  PURPLE = [255, 0, 255]
  YELLOW = [255, 255, 0]
  CYAN = [0, 255, 255]

  # @!endgroup
  
  # @!group Input and Events

  # 指定したキーが押し下げられた時に true を返します。
  #
  # この関数はキーリピートが有効です(つまりキーを押しっぱなしにすると
  # リピート間隔ごとにこの関数は true を返します)。
  # @param keyname [String] キーの名前("ESCAPE"、"F" など)
  #
  # @example
  #     keydown?("X")
  def keydown?(keyname)
    @@keydown.member?(SDL2::Key.keycode_from_name(keyname))
  end

  # 指定したキーが押し下げられた状態であるならば true を返します。
  #
  # @param keyname [String] キーの名前("ESCAPE"、"F" など)
  #
  # @example
  #     keyperssed?("A")
  def keypressed?(keyname)
    SDL2::Key.pressed?(SDL2::Key::Scan.from_name(keyname))
  end

  # 繋っているジョイスティックの数を返します。
  #
  # @note プログラム起動中にジョイスティックを抜き差ししないでください。
  # 
  # @return [Integer]
  # @example
  #
  #      if num_joysticks < 2
  #         messagebox "このゲームにはパッドが2個必要です"
  #         exit
  #      end
  #
  def num_joysticks
    SDL2::Joystick.num_connected_joysticks
  end
  
  # @!group Message box

  # モーダルメッセージボックスを表示します。
  #
  # @param message [String] メッセージ
  # @param title [String] メッセージボックスのウィンドウタイトル
  #        (省略時はスクリプト名)
  # @param type [String] メッセージボックスの種類
  #        ("ERROR", "WARNING", "INFORMATION" のいずれか)
  #
  # @example
  #     messagebox("こんにちは!")
  def messagebox(message, title: nil, type: "INFORMATION")
    flag = case type
           when "INFORMATION"; SDL2::MessageBox::INFORMATION
           when "ERROR"; SDL2::MessageBox::ERROR
           when "WARNING"; SDL2::MessageBox::ERROR
           end
    title ||= @@title
    SDL2::MessageBox.show_simple_box(flag, title, message, nil)
  end

  # @!endgroup

  # @!group Sound
  
  # BGMを演奏開始します。
  #
  # 別のBGMを演奏している状態でこれを呼ぶと
  # そちらの演奏は停止します。
  #
  # ogg や wave を使ってください。mp3もいけると思いますが
  # うまくいかない場合は ogg に変換して使ってください。
  # 
  # @param musicfile [String] 音楽ファイル名
  # @param loop [Integer, "FOREVER"] ループ回数。"FOREVER"でずっと繰り返し。
  # @param fadein [Integer] フェイドインの時間(ミリ秒)。
  #        0 だとフェイドインなしで演奏開始する。
  # @return [void]
  def play_bgm(musicfile, loop = "FOREVER", fadein: 0)
    loop = -1 if loop == "FOREVER"
    SDL2::Mixer::MusicChannel.fade_in(find_music(musicfile), loop, 0)
  end

  # BGMの演奏を止めます。
  # 
  # @param fade_out [Integer] フェイドアウトの時間(ミリ秒)。
  #        0 だとフェイドアウトなしで演奏を停止する。
  # @return [void]
  def stop_bgm(fade_out: 0)
    SDL2::Mixer::MusicChannel.fade_out(fade_out)
  end
  
  private def find_music(file)
    @@musics.fetch(file) {
      @@musics[file] = SDL2::Mixer::Music.load(file)
    }
  end
 
  # @!endgroup

  class CellDefinition
    def initialize(texture, cellwidth, cellheight)
      @cellwidth = cellwidth
      @cellheight = cellheight
      @xsize = texture.w / cellwidth
      @ysize = texture.h / cellheight
    end

    def get_rect(id)
      ny = id / @xsize
      nx = id % @xsize
      if ny >= @ysize
        raise "cellid #{id} is out of range"
      end
      return SDL2::Rect[nx*@cellwidth, ny*@cellheight, @cellwidth, @cellheight]
    end
  end
  private_constant :CellDefinition

  class FPSKeeper
    def initialize(target_fps = 60, skip_limit=15, delay_accuracy = 10)
      @target_fps = target_fps
      @skip_limit = skip_limit
      @delay_accuracy = delay_accuracy
    end

    # タイマーをリセット。メインループの開始直前に呼びだす。
    def reset
      @old_ticks = get_ticks
      @num_skips = 0
    end

    def wait_frame
      now_ticks = get_ticks
      next_ticks = @old_ticks  + (1000.0/@target_fps)
      if next_ticks > now_ticks
        yield
        wait_until(next_ticks)
        @old_ticks = next_ticks
      elsif @num_skips > @skip_limit
        yield
        @num_skips = 0
        @old_ticks = get_ticks
      else
        @old_ticks = now_ticks
      end
    end

    def get_ticks
      SDL2.get_ticks.to_f
    end

    def wait_until(ticks)
      d = ticks - get_ticks
      if d < @delay_accuracy
        while get_ticks < ticks
          # do nothing
        end
      else
        SDL2.delay(Integer(d)) if d > 0
      end
    end
  end
  private_constant :FPSKeeper
end


