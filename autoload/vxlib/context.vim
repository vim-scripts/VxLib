" vim:set fileencoding=utf-8 sw=3 ts=8 et:vim
"
" Author: Marko Mahnič
" Created: April 2010
" License: GPL (http://www.gnu.org/copyleft/gpl.html)
" This program comes with ABSOLUTELY NO WARRANTY.
"
" An infrastructure for writing context-sensitive commands.

if vxlib#plugin#StopLoading('#au#vxlib#context')
   finish
endif

" Calculate the score for a context definition.
" The more the context is defined, the higher the score.
" Since floats don't always work (even with +float), integers are used.
" (when float constants were used, the function crashed with E328)
function! s:CalcContextScore(ctx)
   if a:ctx =~ '\m^[*/]*$'
      return 0
   endif
   let score = 10000
   let factor = 1000
   for part in split(a:ctx, '/')
      let factor += 100
      " oneword
      if part =~ '\m^[^*]\+$'
         let score += factor * 10
         continue
      endif
      " *
      if part =~ '\m^[*]*$'
         continue
      endif
      " *word*
      if part =~ '\m^[*]\+[^*]\+[*]\+$'    
         let score += factor * 1
         continue
      endif
      " *word  or  word*
      if part =~ '\m^[*]\+[^*]\+$'  || part =~ '\m^[^*]\+[*]\+$'
         let score += factor * 2
         continue
      endif
      " word*word
      if part =~ '\m^[^*]\+[*]\+[^*]\+$'
         let score += factor * 4
         continue
      endif
      " ?word*word*...*word?
      if part =~ '\m^\([*]*[^*]\+[*]*)\+$'
         let score += factor * 5
         continue
      endif
   endfor
   return score
endfunc


" Higher scores first.
function! s:CmpContextScore(a, b)
   if a:a[2] < a:b[2] | return 1 | endif
   if a:a[2] > a:b[2] | return -1 | endif
   return 0
endfunc


" Register new context handlers.
"
" @param ctxHandlerList: an existing list (registry) of context handlers.
"     [ ['context', 'handler', score] ... ]
" Every context in the ctxHandlerList is itself a list with these elements:
"     0 - context description
"     1 - the id of the operation to be performed in the context
"     2 - score of the context
"
" Examples of context description: 'python', 'c', 'c/cString', 'c/c*string',
"     '*/*string', '*'
"
" The id of the context handler is usually a string. Another table can be used
" by the application to map handler-ids to functions (see vxlib/manuals_g.vim
" for an example where a help-provider function is selected for the current
" context). A single handler can be used in multiple contexts.
"
" The score for each context in newContextList is calculated in this function.
" The higher the score, the more specific the context definition is (see
" s:CalcContextScore).
"
" @param newContextList: new contexts to be added to the list.
"     [ [ ['context', ...], ['handler', ...] ], ...]
" Every element in the newContextList is a pair of lists. The first list in a
" pair is the list of context. The secont element in a pair is a list of
" handlers. In this function a new context handler is created for each
" combination context:handler from each pair.
" Example:
"    newContextList: [ [['vim', 'help'], ['vimhelp']], [['python'], ['pydoc']] ]
"    -->ctxHandlers: ['vim', 'vimhelp'], ['help', 'vimhelp'], ['python', 'pydoc']
function! vxlib#context#RegisterContextHandlers(ctxHandlerList, newContextList)
   for ctd in a:newContextList
      try
         let [contexts, handlers] = ctd
         for ctx in contexts
            let ctxscore = s:CalcContextScore(ctx)
            for fn in handlers
               let ordscore = (100 - len(a:ctxHandlerList))
               let score = ctxscore + ordscore
               let ctx = tolower(substitute(ctx, '\*', '[^/]*', 'g'))
               call add(a:ctxHandlerList, [ctx, fn, score])
            endfor
         endfor
      catch /.*/
         " TODO: notify errors in context definitions?
         echoe "Error in context definition? " . v:errmsg
      endtry
   endfor
   call sort(a:ctxHandlerList, 's:CmpContextScore')
endfunc


" Get the contexts at the cursor position based on the filetype and the syntax element.
" The contexts are returned as a list: ['filetype', 'filetype/syntax']
function! vxlib#context#GetCursorContext()
   if ! (has('autocmd'))
      return ['']
   endif
   let [nbuf, nline, ncol, noff] = getpos(".")
   let ctx = [&filetype]
   " let syntax = ''
   if has('syntax')
      let synid = synID(nline, ncol, 0)
      let syntax = synIDattr(synid, "name")
      call add(ctx, &filetype . "/" . syntax)
   endif

   " TODO: extensible context detection => ft/syntax ?=> (ft)/(syntax)/specialContext
   "     eg. detect a table inside a vim comment, return customCtx="*/*/texttable"
   "     contexts are: [&ft, &ft . "/" . syntax, customCtx]

   return ctx
endfunc


" Find the handlers in contextHandlerList that are available for contexts in
" cursorContext. The contexts in cursorContext are assumed to be in the
" most-general to most-specific order.
"
" @param ctxHandlerList: @see RegisterContextHandlers
" @param cursorContext: @see GetCrsorContext
" @param findAllMatches: When nonzero, all matches will be found. When zero,
" handlers with jokers in context won't be verified if an exact match is found.
function! vxlib#context#FindContextHandlers(ctxHandlerList, cursorContext, findAllMatches)
   " find the getters for the contexts
   let handlers = []
   let checkAfter = [] " needed if we want all matches
   let contexts = reverse(copy(a:cursorContext))
   for ctx in contexts
      let ctx = tolower(ctx)
      let found = 0
      " Try exact match
      for [patt, hndlr, score] in a:ctxHandlerList " ordered by score (best first)
         if patt == ctx 
            call add(handlers, hndlr)
            let found = 1
         endif
      endfor
      if found
         call add(checkAfter, ctx)
         continue
      endif
      " Try pattern match
      for [patt, hndlr, score] in a:ctxHandlerList
         if match(ctx, '\m\c^' . patt . '$') == 0
            call add(handlers, hndlr)
            let found = 1
         endif
      endfor
   endfor

   if a:findAllMatches
      for ctx in checkAfter
         for [patt, hndlr, score] in a:ctxHandlerList
            if match(ctx, '\m\c^' . patt . '$') == 0
               call add(handlers, hndlr)
            endif
         endfor
      endfor
   endif
   
   let unique = {}
   let result = []
   for hndlr in handlers
      if has_key(unique, hndlr)
         continue
      endif
      let unique[hndlr] = 1
      call add(result, hndlr)
   endfor

   return result
endfunc

