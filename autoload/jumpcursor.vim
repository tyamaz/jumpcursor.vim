" jumpcursor.vim
" Author: skanehira
" License: MIT

" mark 集
let g:jumpcursor_marks = get(g:, 'jumpcursor_marks', split('asdfghjklqwertyuiopzxcvbnmASDFGHJKLQWERTYUIOPZXCVBNM', '\zs'))

" mark の長さ
let s:mark_len = len(g:jumpcursor_marks)

" mark と行の対応を格納
let s:jumpcursor_mark_lnums = {}

" mark と横位置の対応を格納
let s:jumpcursor_mark_cols = {}
" オーバーレイのための名前空間宣言
let s:jumpcursor_ns = nvim_create_namespace('jumpcursor')

" ========================================================================
" mark をオーバーレイで描画する
function! s:draw_mark(bufnr, marklist, linenum, col) abort
  call nvim_buf_set_extmark(a:bufnr, s:jumpcursor_ns, a:linenum - 1, a:col, {
            \ 'virt_text_pos': 'overlay',
            \ 'virt_text': a:marklist
            \ })
endfunction

" ================================================================================
" 画面全体の文字を mark で埋める
" 同時にジャンプ位置の記録も行う
function! s:fill_window() abort
  " 現在のバッファを取得する 対象のバッファは毎度変わる
  let bufnr = bufnr()

  " 画面で見える範囲の先頭行番号を取得する(1始まり換算)
  let start_line = line('w0')
  " 画面で見える範囲の最終行番号を取得する(1始まり換算)
  let end_line = line('w$')

  " 今どの行用 mark を使うのか記録
  let mark_idx = 0

  " 操作対象の行
  let theline = start_line
  " 表示されている先頭から最後の行までループ
  while theline <= end_line
    " mark を使い切ったら終了(行指定で mark を使い切ることはほぼ無い前提)
    if mark_idx >= s:mark_len
      break
    endif
    " 対象行の文字列を1文字ごとにバラバラにした配列で保持(改行は入っていない)
    let text = split(getline(theline), '\zs')

    " その行で最初に使う mark を保持
    let mark = g:jumpcursor_marks[mark_idx]

    " mark に対してジャンプ位置を保持する
    " [ジャンプ行(行番号ベース1スタート換算), 横位置(ベース先頭0ベース)]
    let s:jumpcursor_mark_lnums[mark] = [theline, 0]

    " 空行にも移動できるように先頭に mark する
    if len(text) == 0
      " オーバーレイ表示を予約する
      " この関数は行を0スタート換算するので行番号換算と1だけズレている
      " 先頭行ゼロ位置にオーバーレイする。ここには改行があるので指定してもエラーにならない
      call s:draw_mark(bufnr, [[mark, 'ErrorMsg']], theline, 0)

      " mark を使ったので次のマークに進める
      let mark_idx += 1
      " 対象行が終わったので次の行に進める
      let theline += 1
      " ここで次のループに進める
      continue
    endif

    " 横方向指定で使うことが予想される mark をどこまで使っているか
    " ※ 行指定で今やっている mark ではない
    let col_mark_count = 0

    " 文字数ベースでのジャンプ横位置積算
    " ※ 特定行でしか意味を持たないが特定行に紐付いた値なので
    let jumpx = 0
    
    " mark 埋め込み用の配列
    let filling = []
    
    " 文字ベースで foreach的な
    for i in range(len(text))
      " スペース分を足す
      if text[i] == ' ' || text[i] == "\t"
        " 正味の位置をズラして次
        call add(filling, [' ', 'NonText'])
        let jumpx += 1
        continue
      endif

      " 横置選択で mark が足りなくなることを予想して行の途中で mark を次に進める
      " ※ 行選択では mark が枯渇しない前提
      " 横方向指定で使うことが予想される mark を使い切ってしまった
      if col_mark_count == s:mark_len
        " 横方向予想に使うカウンタを初期化
        let col_mark_count = 0
        " 使う行用の mark を次にm進める
        let mark_idx += 1
        " mark を更新
        let mark = g:jumpcursor_marks[mark_idx]
        " 行と開始位置を記録しておく
        " 結果として複数の mark に同一の行が割り当てられる可能性がある
        let s:jumpcursor_mark_lnums[mark] = [theline, jumpx]
      endif 


      " 実際に挿入される mark を換算
      let insertmark = mark
      " 日本語対応
      if strwidth(text[i]) == 2
          let insertmark .= ' '
      endif

      call add(filling, [insertmark, 'ErrorMsg'])

      " mark の長さと行の長さを比べるためにカウント
      let col_mark_count += 1
      " 実際にジャンプする位置を記録特定行の文字数ベースで記録するのでマルチバイト関係無い
      let jumpx += 1
    endfor

    call s:draw_mark(bufnr, filling, theline, 0)

    " 行が変わるので次の mark 次の行に進める
    let mark_idx += 1
    let theline += 1
  endwhile
endfunction

" ================================================================================
" 行を mark で埋める
" 引数 [行番号(1起算), 埋め起点の文字数ベース]
function! s:fill_specific_line(lnum) abort
  let bufnr = bufnr()
  " 対象行の文字列を1文字ごとの配列に分解して保持
  let text = split(getline(a:lnum[0]), '\zs')

  " ジャンプ位置積算(バイト数ベース) 初期化
  let jumpxb = 0
  " 描画位置積算(半角文字数ベース) 初期化
  let jumpxc = 0
  for i in range(len(text))
    " スタート位置までジャンプ位置を積算する
    " 0指定なら入らない
    if i < a:lnum[1]
      let jumpxb += len(text[i])
      let jumpxc += strwidth(text[i])
    endif
  endfor

  " 使う mark 指定
  let mark_idx = 0
  
  " 対象行下行に出すジャンプのための mark の集合体
  " 都度指定すると行末以降指定できないのでまとめて行頭指定するため
  let ruler = [] 
  " 行に対して mark の切り替え位置分だけスペースを挟み込む
  for i in range(jumpxc)
      call add(ruler, [' ', 'NonText'])
  endfor

  
  " 行を1文字ずつループ
  " 起点からケツまで
  for i in range(a:lnum[1], len(text) - 1)
    " mark が枯渇したら終了
    " その範囲を markするようにそもそも狙っている
    if mark_idx >= s:mark_len
      break
    endif

    if text[i] ==# ' ' || text[i] ==# "\t"
      " スペースはスペースとして足す
      call add(ruler, [' ', 'NonText'])
      " スペース分だけ1つ位置を進める
      " ジャンプは文字のバイト列換算で行われるのでマルチバイト文字の場合の長さでシフトする
      let jumpxb += len(text[i])
      continue
    endif

    " 使う mark 確定
    let mark = g:jumpcursor_marks[mark_idx]
    " mark を積算
    call add(ruler, [mark, 'ErrorMsg'])
    " その位置で記録 対象の先頭
    let s:jumpcursor_mark_cols[mark] = jumpxb 

    " ジャンプは文字のバイト列換算で行われるのでマルチバイト文字の場合の長さでシフトする
    let jumpxb += len(text[i])
    " 全角対応
    if strwidth(text[i]) == 2
        call add(ruler, [' ', 'ErrorMsg'])
    endif
    " 次の mark へ進める
    let mark_idx += 1
  endfor

  " ここに入っている値は 1スタート換算 なのでそのままだと、対象の1個下の行となる(0スタート換算)
  let rulerline = a:lnum[0]
  if a:lnum[0] == line('w$')
      " 1個上の行に入れたい
      let rulerline = a:lnum[0] - 2
  endif
  
  " 次の行に描画する
  call s:draw_mark(bufnr, ruler, rulerline + 1, 0)

  redraw!
endfunction


" ================================================================================
" エントリーポイントの関数ー
function! jumpcursor#jump() abort
  " 全行 mark で埋める
  call s:fill_window()
  redraw!
  " キー入力うけつけ
  let mark = getcharstr()

  " 全行埋めたオーバーレイを消す
  call s:jump_cursor_clear()
  redraw!

  " ジャンプできる入力のみうけつけ
  if mark ==# '' || mark ==# ' ' || !has_key(s:jumpcursor_mark_lnums, mark)
    return
  endif

  " markとその情報を取り出す
  " [行番号(1起算), mark切り替わり位置]
  let lnum = s:jumpcursor_mark_lnums[mark]

  " 行取得
  let linetext = getline(lnum[0])

  " 空行、もしくは1文字しかないなら横位置選ばずに先頭へ飛ぶ
  if len(linetext) <= 1
    call setpos('.', [bufnr(), lnum[0], 0, 0])
    let s:jumpcursor_mark_lnums = {}
    let s:jumpcursor_mark_cols = {}
    return
  endif

  " 行情報を使って行内ジャンプのガイドを描画する
  call s:fill_specific_line(lnum)

  let mark = getcharstr()
  call s:jump_cursor_clear()

  if mark ==# '' || mark ==# ' ' || !has_key(s:jumpcursor_mark_cols, mark)
    return
  endif

  let col = s:jumpcursor_mark_cols[mark] + 1

  call setpos('.', [bufnr(), lnum[0], col, 0])
  " call setpos('.', [bufnr(), lnum[0], 10, 0])
  let s:jumpcursor_mark_lnums = {}
  let s:jumpcursor_mark_cols = {}
endfunction

" ================================================================================
" mark を消す
function! s:jump_cursor_clear() abort
  call nvim_buf_clear_namespace(bufnr(), s:jumpcursor_ns, line('w0')-1, line('w$'))
endfunction
