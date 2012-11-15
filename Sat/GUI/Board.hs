-- | Renderiza el board para la interfaz en base a un archivo SVG.
module Sat.GUI.Board where

import Control.Monad 
import Control.Monad.Trans.RWS (ask,evalRWST,get,RWST)

import Lens.Family

import Data.Maybe
import Data.Char (isUpper)
import qualified Data.List as L
import qualified Data.Map as M

import Graphics.UI.Gtk hiding ( eventButton, eventRegion, eventClick
                              , eventKeyName, get
                              )
import Graphics.UI.Gtk.Gdk.Events

import Graphics.Rendering.Cairo
import Graphics.Rendering.Cairo.SVG

import Sat.Core
import Sat.VisualModel (visualToModel)
import Sat.VisualModels.FiguresBoard

import Sat.GUI.SVG
import Sat.GUI.SVGBoard
import Sat.GUI.GState
import Sat.GUI.IconTable
import Sat.GUI.FigureList

whenM dont may does = maybe dont does may

hSpacing :: Double
hSpacing = 20

flipEvalRWST :: Monad m => r -> s -> RWST r w s m a -> m (a, w)
flipEvalRWST r s rwst = evalRWST rwst r s

getPointerCoord = 
    displayGetDefault >>= maybe (return Nothing) 
                                (liftM Just . displayGetPointer) >>=
    return . maybe Nothing (\(_,_,x,y) -> Just (x,y))

configDrag :: DrawingArea -> IO ()
configDrag da = do
        dragSourceSet da [Button1,Button2] [ActionCopy]
        dragSourceSetIconStock da stockAdd
        dragSourceAddTextTargets da

        da `on` dragDataGet $ \dc ifd ts -> do
               mcoord <- io getPointerCoord
               whenM (return ()) mcoord $ \coord -> do
               selectionDataSetText (show coord)
               return ()
        return ()

parseCoord :: String -> (Int,Int)
parseCoord = read

-- | Función principal para el render del board.
configRenderBoard :: SVG -> GuiMonad ()
configRenderBoard svgboard = ask >>= \content -> get >>= \s -> io $ do
    let da = content ^. gSatDrawArea

    configDrag da

    dragDestSet da [DestDefaultMotion, DestDefaultDrop] [ActionCopy]
    dragDestAddTextTargets da
    da `on` dragDataReceived $ \dc (x,y) id ts -> do
          mstr <- selectionDataGetText
          whenM (return ()) mstr $ \str -> io $ do
            let (srcX, srcY) = parseCoord str
            squareDst <- getSquare (toEnum x) (toEnum y) da
            io $ putStrLn ("Dst: " ++ show squareDst)
            squareSrc <- getSquare (toEnum srcX) (toEnum srcY) da
            io $ putStrLn ("Src: " ++show squareSrc)
            whenM (return ()) squareSrc $ \(colSrc,rowSrc) ->  do
                (meb,()) <- evalRWST (getEBatCoord colSrc rowSrc) content s
                whenM (return ()) meb $ \ eb -> do
                  putStrLn (show (colSrc,rowSrc))
                  (st,_) <- evalRWST getGState content s
                  let board  = st ^. gSatBoard
                      elemsB = elems board
                  whenM (return ()) squareDst $ \ (col,row) -> do
                      evalRWST (addNewElem (Coord col row) elemsB board >>= 
                               \(board,i,avails) -> 
                                updateBoardState avails i board) content s
                      widgetQueueDraw da


    da `onExpose` \expose ->
        flipEvalRWST content s (drawBoard da expose) >> 
        return False
    
    return ()
    where
        drawBoard :: DrawingArea -> Event -> GuiMonad Bool
        drawBoard da expose = getGState >>= \st -> io $ do
            let exposeRegion = eventRegion expose
                board = st ^. gSatBoard
            drawWindow              <- widgetGetDrawWindow da
            (drawWidth, drawHeight) <- liftM (mapPair fromIntegral) $ widgetGetSize da

            drawWindowClear drawWindow
            renderWithDrawable drawWindow $ do
                let (boardWidth, boardHeight) = mapPair fromIntegral $ svgGetSize svgboard
                    sideSize = min drawWidth drawHeight - hSpacing
                    xoffset  = (drawWidth - sideSize) / 2
                    yoffset  = (drawHeight - sideSize) / 2
                region exposeRegion
                
                translate xoffset yoffset
                
                save
                scale (sideSize / boardWidth) (sideSize / boardHeight)
                svgRender svgboard
                restore
                
                renderElems board sideSize
            return False

renderElems :: Board -> Double -> Render ()
renderElems b sideSize = 
    forM_ (elems b) $ \(Coord x y, e) -> do
        svgelem <- io $ generateSVGFromEB boardMain boardMod e
        let squareSize = sideSize / realToFrac (size b)
            (width, height) = mapPair fromIntegral (svgGetSize svgelem)
        
        save
        translate (squareSize * fromIntegral (toEnum x)) (squareSize * fromIntegral (toEnum y))
        scale (squareSize / width) (squareSize / height)
        svgRender svgelem
        restore
        
        case ebConstant e of
            Nothing -> return ()
            Just c  -> do
                save
                let posx = squareSize * fromIntegral (toEnum x)
                    posy = squareSize * fromIntegral (toEnum y)
                la <- createLayout (constName c)
                io $ layoutSetAttributes la [AttrSize 0 2 10.0]
                translate (posx + (squareSize / 2.0) - 5.0) (posy + (squareSize / 2.0) - 5.0)
                showLayout la
                restore

getSquare :: Double -> Double -> DrawingArea -> IO (Maybe (Int,Int))
getSquare x y da = do
        (drawWidth, drawHeight) <- liftM (mapPair fromIntegral) $ widgetGetSize da
        let sideSize   = min drawWidth drawHeight - hSpacing
            squareSize = sideSize / 8
            xoffset    = (drawWidth - sideSize) / 2
            yoffset    = (drawHeight - sideSize) / 2
        if (x >= xoffset && x < xoffset + sideSize && 
            y >= yoffset && y < yoffset + sideSize)
        then return $ Just ( floor ((x - xoffset) / squareSize)
                           , floor ((y - yoffset) / squareSize))
        else return Nothing


configDrawPieceInBoard :: SVG -> GuiMonad ()
configDrawPieceInBoard b = ask >>= \content -> get >>= \rs -> io $ do
    let da = content ^. gSatDrawArea
    da `onButtonPress` \Button { eventButton = button
                               , eventClick = click
                               , eventX = x
                               , eventY = y
                               } -> do
      square <- getSquare x y da
      flip (maybe (return False)) square $ \ (colx,rowy) -> do
          case (button,click) of
            (LeftButton,SingleClick) -> do
                    evalRWST (addElemBoardAt colx rowy) content rs
                    widgetQueueDraw da
                    return True
            (RightButton,SingleClick) -> do
                    evalRWST (deleteElemBoardAt colx rowy) content rs
                    widgetQueueDraw da
                    return True
            _ -> return False
    return ()
    where
        deleteElemBoardAt :: Int -> Int -> GuiMonad ()
        deleteElemBoardAt colx rowy = do
            st <- getGState
            let board = st ^. gSatBoard
                elemsB = elems board 
                
                cords = Coord colx rowy
                elemToDelete = lookup cords elemsB
            
            when (isJust elemToDelete) (updateBoardState cords board (fromJust elemToDelete) elemsB)
            where
                updateBoardState :: Coord -> Board -> ElemBoard -> 
                                    [(Coord,ElemBoard)] -> GuiMonad ()
                updateBoardState cords board elemToDelete elemsB = 
                    ask >>= \content -> getGState >>= \st -> do
                    let avails  = st ^. (gSatPieceToAdd . eaAvails)
                        elems'  = L.delete (cords,elemToDelete) elemsB
                        avails' = uElemb elemToDelete : avails
                        iconEdit = content ^. gSatMainStatusbar
                        
                    updateGState ((<~) gSatBoard board{elems = elems'})
                    updateGState ((<~) (gSatPieceToAdd . eaAvails) avails')
                    makeModelButtonWarning

getEBatCoord :: Int -> Int -> GuiMonad (Maybe ElemBoard)
getEBatCoord col row = do 
            let coord = Coord col row
            
            st <- getGState
            let board  = st ^. gSatBoard
                elemsB = elems board
            
            return $ lookup coord elemsB
        
addElemBoardAt :: Int -> Int -> GuiMonad ()
addElemBoardAt colx rowy = do
           
            st <- getGState
            let board  = st ^. gSatBoard
                elemsB = elems board

            let coord = Coord colx rowy
            meb <- getEBatCoord colx rowy
            case meb of
                Just eb -> addNewTextElem coord eb elemsB board
                Nothing -> addNewElem coord elemsB board >>= \(board,i,avails) ->
                           updateBoardState avails i board
            where
                addNewTextElem :: Coord -> ElemBoard -> [(Coord,ElemBoard)] -> 
                                  Board -> GuiMonad ()
                addNewTextElem coord eb elemsB board = 
                    ask >>= \content -> getGState >>= \st -> get >>= \stRef ->
                    io $ do
                    let avails = st ^. (gSatPieceToAdd . eaAvails)
                        i      = st ^. (gSatPieceToAdd . eaMaxId)
                        mainWin = content ^. gSatWindow
                    
                    win   <- windowNew
                    entry <- entryNew
                    
                    set win [ windowWindowPosition := WinPosMouse
                            , windowModal          := True
                            , windowDecorated      := False
                            , windowHasFrame       := False
                            , windowTypeHint       := WindowTypeHintPopupMenu
                            , widgetCanFocus       := True
                            , windowTransientFor   := mainWin
                            ]
                    
                    containerAdd win entry
                    widgetShowAll win
                    
                    entrySetText entry $ maybe "" constName (ebConstant eb)
                    
                    onKeyPress entry (configEntry win entry content stRef)
                    
                    return ()
                    where
                        configEntry :: Window -> Entry -> GReader -> 
                                       GStateRef -> Event -> IO Bool
                        configEntry win entry content stRef e = do
                            cNameOk <- if eventKeyName e == "Return"
                                            then updateEb entry content stRef
                                            else return False
                            if cNameOk
                               then widgetDestroy win >>
                                    widgetQueueDraw (content ^. gSatDrawArea) >>
                                    evalRWST makeModelButtonWarning content stRef >>
                                    return False
                               else return False
                        updateEb :: Entry -> GReader -> GStateRef -> IO Bool
                        updateEb entry content stRef = do
                            cName <- entryGetText entry
                            if checkConstantName cName
                               then flipEvalRWST content stRef (do
                                        let elemsB' = map (assigConst cName) elemsB
                                            board'  = board {elems = elemsB'}
                                        updateGState ((<~) gSatBoard board')
                                        ) >> return True
                               else return False
                        checkConstantName :: String -> Bool
                        checkConstantName str =  length str <= 2 
                                              && all isUpper str 
                                              && all (checkDoubleConst str) elemsB
                        checkDoubleConst :: String -> (Coord,ElemBoard) -> Bool
                        checkDoubleConst str (_,eb') = 
                            if eb' == eb
                               then True
                               else Just (Constant str) /=  ebConstant eb'
                        assigConst :: String -> (Coord,ElemBoard) -> 
                                      (Coord,ElemBoard)
                        assigConst [] (coord',eb') =
                            if coord == coord'
                               then (coord',eb' {ebConstant = Nothing})
                               else (coord',eb')
                        assigConst cName (coord',eb') =
                            if coord == coord'
                               then (coord',eb' {ebConstant = Just $ Constant cName})
                               else (coord',eb')
                
addNewElem :: Coord -> [(Coord,ElemBoard)] -> Board -> 
              GuiMonad (Board,Univ,[Univ])
addNewElem coord elemsB board = do
    (eb,i,avails) <- newElem coord
    let e = (coord,eb)
    
    return (board {elems = e : elemsB},i,avails)

newElem :: Coord -> GuiMonad (ElemBoard,Univ,[Univ])
newElem coord = do
    st <- getGState
    let preds  = st ^. (gSatPieceToAdd . eaPreds)
        avails = st ^. (gSatPieceToAdd . eaAvails)
        i      = st ^. (gSatPieceToAdd . eaMaxId)
    
    return $ 
        if avails == []
            then (ElemBoard (i + 1) Nothing preds,i + 1,avails)
            else (ElemBoard (head avails) Nothing preds,head avails,tail avails)

updateBoardState :: [Univ] -> Univ -> Board -> GuiMonad ()
updateBoardState avails i board = ask >>= \content -> do 
    let iconEdit = content ^. gSatMainStatusbar
    
    updateGState ((<~) gSatBoard board)
    updateGState ((<~) (gSatPieceToAdd . eaMaxId) i)
    updateGState ((<~) (gSatPieceToAdd . eaAvails) avails)
    makeModelButtonWarning



makeModelFromBoard :: GuiMonad ()
makeModelFromBoard = getGState >>= \st -> do
    let visual = st ^. gSatBoard
        model  = visualToModel visual
        
    updateGState ((<~) gSatModel model)
    makeModelButtonOk
