" vim: fileencoding=utf-8
" python.vim - Prepare vim/python to use loadable modules
"
" Author: Marko Mahnič
" Created: April 2009
" License: GPL (http://www.gnu.org/copyleft/gpl.html)
" This program comes with ABSOLUTELY NO WARRANTY.
"
" Intended use:
" function ExampleUsesPythonModule()
"    call vxlib#python#prepare()
"    python << EOF
"    import my_vim_module   # my_vim_module.py installed in ~/.vim/modpython
"    ...
"    EOF
" endfunc

if vxlib#plugin#StopLoading('#au#vxlib#python')
   finish
endif

" Add ~/.vim/modpython to python search path.
" Vim-python modules should be installed in ~/.vim/modpython
function! vxlib#python#prepare()
   if has('python') && !exists('s:pypath')
      let s:pypath = split(globpath(&runtimepath, 'modpython'), "\n")
      python import sys
      for pth in s:pypath
         exec "python sys.path.append(r'" . pth . "')"
      endfor
      let s:pypath = []
   endif
endfunc

