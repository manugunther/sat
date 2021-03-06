-- | Undo and redo actions.
module Sat.GUI.UndoRedo where

import Control.Lens


import Control.Monad.Trans.RWS

import Graphics.UI.Gtk

import Sat.GUI.GState
import Sat.GUI.EntryFormula
                
undoAction :: GuiMonad ()
undoAction =
    getGState >>= \st ->
    ask >>= \cnt ->
    let (urlist,i) = st ^. gURState in
      if length(drop (i+1) urlist) == 0
        then return ()
        else do
                let newState = urlist!!(i+1)
                    board = newState ^. urBoard
                    flist = newState ^. urFList
                    prevPToAdd = st ^. gSatPieceToAdd
                    pToAdd = newState ^. urPieceToAdd
                    pToAdd' = pToAdd {_eaPreds = _eaPreds prevPToAdd}
                    
                    gst = st { _gSatBoard = board
                             , _gSatFList = flist
                             , _gSatPieceToAdd = pToAdd'
                             , _gSatDNDSrcCoord = Nothing
                             , _gURState = (urlist,i+1)
                    }
                    da = cnt ^. gSatDrawArea
             
                updateGState (const gst)
                createNewEntryFormulaList flist
                io $ widgetQueueDraw da
                
                return ()

redoAction :: GuiMonad ()
redoAction =
    getGState >>= \st ->
    ask >>= \cnt ->
    let (urlist,i) = st ^. gURState in
      if i == 0
        then return ()
        else do
                let newState = urlist!!(i-1)
                    board = newState ^. urBoard
                    flist = newState ^. urFList
                    pToAdd = newState ^. urPieceToAdd
                    
                    gst = st { _gSatBoard = board
                             , _gSatFList = flist
                             , _gSatPieceToAdd = pToAdd
                             , _gSatDNDSrcCoord = Nothing
                             , _gURState = (urlist,i-1)
                    }
             
                    da = cnt ^. gSatDrawArea
             
                updateGState (const gst)
                createNewEntryFormulaList flist
                io $ widgetQueueDraw da
                
                return ()
