" vim:set fileencoding=utf-8 sw=3 ts=8 et:vim
" menu.vim - select a backend to display a (popup) menu
"
" Author: Marko Mahnič
" Created: May 2010
" License: GPL (http://www.gnu.org/copyleft/gpl.html)
" This program comes with ABSOLUTELY NO WARRANTY.

if vxlib#plugin#StopLoading('#au#vxlib#menu')
   finish
endif

" =========================================================================== 
" Local Initialization - on autoload
" =========================================================================== 
let s:has_vxtextmenu = exists('*vimuiex#vxtextmenu#VxTextMenu')
   \ || vxlib#plugin#PluginExists('vimuiex#vxtextmenu', 'autoload/vimuiex/vxtextmenu.vim')

" supported modes: vimuiex, popup, choice
" (Is it possible to use :emenu here? it seems that I need to map-<expr>, so NO)
let s:BackendOrder = ['vimuiex', 'popup', 'choice'] " 'emenu'
" =========================================================================== 

function! s:CheckExtraSettings()
   if exists('g:vxlib_menu_backend_order') 
      if !empty(g:vxlib_menu_backend_order)
         let neworder = copy(g:vxlib_menu_backend_order)
         for mm in s:BackendOrder
            if index(neworder, mm) >= 0
               continue
            endif
            call add(neworder, mm)
         endfor
         let s:BackendOrder = neworder
      endif
      unlet g:vxlib_menu_backend_order
   endif
endfunc

" requires: +menu
function! vxlib#menu#DoVimMenu(menuPath, backend)
   call s:CheckExtraSettings()
   let mback = a:backend
   if !index(s:BackendOrder, mback) < 0 | let mback = s:BackendOrder[0] | endif
   let vimmode = 'n' " TODO vimmode as parameter
   let name = a:menuPath

   let cando = {}
   let cando['vimuiex'] = s:has_vxtextmenu && has('menu') && has('python') 
            \ && (!has('gui_running') || has('python_screen'))
   let cando['popup'] = has('menu') && has('gui_running')
   " let cando['emenu'] = has('menu')
   let cando['choice'] = has('menu') 

   if !cando[mback]
      let newback = ''
      for mm in s:BackendOrder
         if cando[mm]
            let newback = mm
            break
         endif
      endfor
      if newback == ''
         echoe "Unable to display menu."
         return
      endif
      let mback = newback
   endif

   if mback == 'vimuiex'
      call vimuiex#vxtextmenu#VxTextMenu(name, vimmode)
      exec vimmode . 'unmenu ' . name
   elseif mback == 'popup'
      exec 'popup ' . name
   "elseif mback == 'emenu'
   "   if !exists("did_install_default_menus") || !did_install_default_menus
   "      source $VIMRUNTIME/menu.vim
   "   endif
   "   exec 'norm :emenu ' . name
   elseif mback == 'choice'
      call s:ChoiceVimMenu([name], vimmode)
   endif
endfunc

" TODO: define the structure for items
function! vxlib#menu#DoMenu(items, backend)
   call s:CheckExtraSettings()
   let mback = a:backend
   if !index(s:BackendOrder, mback) < 0 | let mback = s:BackendOrder[0] | endif

   let cando = {}
   let cando['vimuiex'] = s:has_vxtextmenu && has('python')
            \ && (!has('gui_running') || has('python_screen'))
   let cando['popup'] = 0
   " let cando['emenu'] = 0
   let cando['choice'] = 1
   
   " TODO: parse items and display the menu
   echoe "DoMenu not implemented. Try DoVimMenu."
endfunc

function! vxlib#menu#GetMenuTitles(menuPath, vimmode)
   if type(a:menuPath) == type([])
      if len(a:menuPath) > 0 && a:menuPath[0] == ''
         let menuPath = join(map(copy(a:menuPath[1:]), 'escape(v:val," .")'), '.')
      else
         let menuPath = join(map(copy(a:menuPath), 'escape(v:val," .")'), '.')
      endif
   else
      let menuPath = a:menuPath
   endif
   " select the correct menu depending on current mode
   let lmns = vxlib#cmd#Capture(a:vimmode . 'menu ' . menuPath, 1)
   let themenu = []
   for line in lmns
      let text = ''
      let cmd = ''
      let mtitle = matchstr(line, '^\s*\d\+\s.\+') | " space digit space any
      if mtitle != ''
         let mtitle=substitute(mtitle, '^\(\s*\)\d\+\s\(.\+\)$', "\\1|\\2", '')
         call add(themenu, mtitle)
      endif
   endfor
   unlet lmns
   return themenu
endfunc

function! s:ChoiceVimMenu(menuPathList, mode)
   let menuPath = a:menuPathList
   let allSubmenus = vxlib#menu#GetMenuTitles(menuPath, a:mode)
   if !(len(menuPath) == 1 && menuPath[0] == '')
      let allSubmenus = allSubmenus[1:]
   endif
   if len(allSubmenus) < 1
      let curlevel = 0
   else
      let curlevel = len(matchstr(allSubmenus[0], '^\s*'))
   endif
   let pos = 0
   let choices = []
   for i in range(len(allSubmenus))
      let item = allSubmenus[i]
      let level = len(matchstr(item, '^\s*'))
      if level != curlevel
         continue
      endif
      let item = split(matchstr(item, '\s*|\zs.*'), '\^I')[0]
      if item =~ '^-SEP'
         call add(choices, ['', '-', 0])
      else
         let pos += 1
         let qc = '' . pos
         let nextlevel = level
         if  i < len(allSubmenus) - 1
            let nextlevel = len(matchstr(allSubmenus[i+1], '^\s*'))
         endif
         if nextlevel > level | let subm = 1
         else | let subm = 0
         endif
         call add(choices, [qc, item, subm])
      endif
   endfor

   if len(choices) < 1
      if len(menuPath) > 1 | return 0
      else | return -1
      endif
   endif
   if len(menuPath) > 1
      call add(choices, ['99', '(Go Up)', 0])
   endif

   unlet item
   let mdisp = []
   for item in choices
      if item[1] == '-' | call add(mdisp, '-------------------')
      else
         let str = printf('%2s. %s', item[0], substitute(item[1], '&', '', 'g'))
         if item[2] | let str = str . ' >>>' | endif
         call add(mdisp, str)
      endif
   endfor
   let nsel = 0
   while nsel == 0
      echo '[   Menu: ' . join(menuPath, '.') . ']'
      let sel = inputlist(mdisp)
      if sel == '' | return -1 | endif " Cancelled
      let nsel = 0 + sel
      if nsel == 99 " Go Up or Cancel
         if len(menuPath) > 1 | return 0
         else | return -1
         endif
      endif
      let selected = []
      for item in choices
         if item[0] == sel
            let selected = item
            break
         endif
      endfor
      if len(selected) < 1
         echoe "Invalid menu choice " . nsel
         return -1
      endif
      let newPath = copy(menuPath)
      call add(newPath, selected[1])
      if selected[2] " submenu
         redraw!
         let nsel = s:ChoiceVimMenu(newPath, a:mode)
         if nsel == 0 | redraw! | endif
      else
         if newPath[0] == '' | let newPath = newPath[1:] | endif
         let selmenu = join(map(newPath, 'escape(v:val," .")'), '.')
         " TODO: execute in the right mode
         exec 'emenu ' . selmenu
         break
      endif
   endwhile
   return -1
endfunc

