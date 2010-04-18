" vim:set fileencoding=utf-8 sw=3 ts=3 et:vim
"
" Author: Marko Mahnič
" Created: April 2010
" License: GPL (http://www.gnu.org/copyleft/gpl.html)
" This program comes with ABSOLUTELY NO WARRANTY.
"
" Frontend for the Vim Plugin Generator
" The commands are defined in plugin/vxlib.vim

if vxlib#plugin#StopLoading('#au#vxlib#pluggen')
   finish
endif

function! s:FindConfig(createDir)
   let locs = split(globpath(&rtp, 'plugin/vxplugin.conf'), "\n")
   if len(locs) > 0
      let plugfile = locs[0]
   else
      let locs = split(globpath(&rtp, 'plugin'), "\n")
      if len(locs) > 0
         let plugfile = locs[0] . '/vxplugin.conf'
      elseif a:createDir
         locs = split(&rtp, ',')
         if len(locs) > 0
            call mkdir(locs[0] . '/plugin')
            let plugfile = locs[0] . '/plugin/vxplugin.conf'
         else
            echoe "Can't find a place to store vxplugin.conf (eg. ~/.vim/plugin)"
            return ''
         endif
      endif
   endif
   return resolve(expand(plugfile))
endfunc

" XXX These paths are highly unreliable becaue Vim can't tell me which is
" the users primary directory for his Vim stuff.
function! vxlib#pluggen#GeneratePlugins()
   let locs = split(globpath(&rtp, 'modpython/vxlib/plugin.py'), "\n")
   if len(locs) < 1
      return
   endif

   let plugfile = s:FindConfig(1)
   if bufexists(plugfile)
      let curbuf = bufnr('%')
      silent exec 'buffer ' . plugfile
      if &modified
         write
      endif
      silent exec 'buffer ' . curbuf
   endif

   let generator = locs[0]
   let locs = split(globpath(&rtp, 'plugin'), "\n")
   let plugins = locs[0]
   let locs = split(globpath(&rtp, 'autoload'), "\n")
   let cmd = generator . ' ' . join(locs, ' ') .
            \  ' -o ' . plugins . '/_vimuiex_autogen_.vim' .
            \  ' --update --config ' . plugins . '/vxplugin.conf'
   silent exec '!python ' . cmd
   echom 'Plugins regenerated.'
   echom 'You must restart Vim for the changes to take effect.'
endfunc

function! vxlib#pluggen#ConfigurePlugins()
   let plugfile = s:FindConfig(1)
   exec 'edit ' . plugfile
endfunc
