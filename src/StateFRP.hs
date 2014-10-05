{-# LANGUAGE PackageImports #-}
import "GLFW-b" Graphics.UI.GLFW as GLFW
import Graphics.Rendering.OpenGL hiding (Front)
import System.Exit ( exitWith, ExitCode(ExitSuccess) )
import Control.Concurrent (threadDelay)
import Control.Monad (when, join)
import Control.Monad.Fix (fix)
import Control.Applicative ((<*>), (<$>))
import FRP.Elerea.Simple
import Foreign.C.Types (CDouble(..))
import System.Random

type Pos = Vector2 GLdouble
data Player = Player Pos
type Hunting = Bool
data Monster = Monster Pos Hunting Walking
               deriving Show

data Walking = Wander Direction Int
               deriving Show
data Direction = WalkUp | WalkDown | WalkLeft | WalkRight
                 deriving (Show, Enum, Bounded)

instance Random Direction where
  randomR (a, b) g = case randomR (fromEnum a, fromEnum b) g of
                       (x, g') -> (toEnum x, g')
  random g = randomR (minBound, maxBound) g

initialPlayer = Player (Vector2 200 200)
initialMonster = Monster (Vector2 400 400) False (Wander WalkUp wanderDist)
width = 640
height = 640
playerSize = (20 :: GLdouble)
monsterSize = (20 :: GLdouble)
monsterSpeed = 5

initGL width height = do
  clearColor $= Color4 1 1 1 1
  viewport $= (Position 0 0, Size (fromIntegral width) (fromIntegral height))
  ortho 0 (fromIntegral width) 0 (fromIntegral height) (-1) 1

main :: IO ()
main = do
    (directionKey, directionKeySink) <- external (False, False, False, False)
    randomGenerator <- newStdGen
    let randomSeries = randoms randomGenerator
    withWindow width height "Game-Demo" $ \win -> do
          initGL width height
          network <- start $ do
            player <- transfer initialPlayer (\p dK -> movePlayer p dK 10) directionKey
            randomS <- stateful randomSeries pop
            monster <- transfer2 initialMonster wanderOrHunt player randomS
            return $ renderFrame win <$> player <*> monster <*> randomS
          fix $ \loop -> do
               readInput win directionKeySink
               join network
               threadDelay 20000
               esc <- keyIsPressed win Key'Escape
               when (not esc) loop
          exitWith ExitSuccess

pop (x:xs) = xs

readInput window directionKeySink = do
    pollEvents
    l <- keyIsPressed window Key'Left
    r <- keyIsPressed window Key'Right
    u <- keyIsPressed window Key'Up
    d <- keyIsPressed window Key'Down
    directionKeySink (l, r, u, d)

movePlayer (True, _, _, _) (Player (Vector2 xpos ypos)) increment
         | xpos <= playerSize/2 = Player (Vector2 xpos ypos)
         | otherwise = Player (Vector2 (xpos - increment) ypos)
movePlayer (_, True, _, _) (Player (Vector2 xpos ypos)) increment
         | xpos >= (fromIntegral(width) - playerSize/2) = Player (Vector2 xpos ypos)
         | otherwise = Player (Vector2 (xpos + increment) ypos)
movePlayer (_, _, True, _) (Player (Vector2 xpos ypos)) increment
         | ypos >= (fromIntegral(height) - playerSize/2) = Player (Vector2 xpos ypos)
         | otherwise = Player (Vector2 xpos (ypos + increment))
movePlayer (_, _, _, True) (Player (Vector2 xpos ypos)) increment
         | ypos <= playerSize/2 = Player (Vector2 xpos ypos)
         | otherwise = Player (Vector2 xpos (ypos - increment))
movePlayer (False, False, False, False) (Player (Vector2 xpos ypos)) increment = Player (Vector2 xpos ypos)

wanderDist = 40
huntingDist = 100
wanderOrHunt player randomSeries monster = if close player monster
                                              then hunt player monster
                                              else wander randomSeries monster

close (Player (Vector2 xpos ypos)) (Monster (Vector2 xmon ymon) _ _) = ((xpos - xmon)^2 + (ypos - ymon)^2) < huntingDist^2


-- if player is upper left quadrant, diagonal left
-- means xpos > xmon and ypos > ymon
hunt player@(Player (Vector2 xpos ypos)) monster@(Monster (Vector2 xmon ymon) _ _) 
  | (xpos > xmon) && (ypos > ymon) = Monster (Vector2 (xmon + monsterSpeed) (ymon + monsterSpeed)) True (Wander WalkUp wanderDist)
  | (xpos <= xmon) && (ypos > ymon) = Monster (Vector2 (xmon - monsterSpeed) (ymon + monsterSpeed)) True (Wander WalkUp wanderDist)
  | (xpos <= xmon) && (ypos <= ymon) = Monster (Vector2 (xmon - monsterSpeed) (ymon - monsterSpeed)) True (Wander WalkUp wanderDist)
  | (xpos > xmon) && (ypos <= ymon) = Monster (Vector2 (xmon + monsterSpeed) (ymon - monsterSpeed)) True (Wander WalkUp wanderDist)

-- turn in random direction
wander randomSeries (Monster (Vector2 xmon ymon) hunting (Wander direction 0)) = Monster (Vector2 xmon ymon) False (Wander (head randomSeries) wanderDist)
-- go straight
wander _ (Monster (Vector2 xmon ymon) hunting (Wander WalkUp n))
  | ymon < (fromIntegral(height) - monsterSize/2) = Monster (Vector2 xmon (ymon + monsterSpeed)) False (Wander WalkUp (n-1))
  | otherwise = Monster (Vector2 xmon ymon) False (Wander WalkDown (n-1))
wander _ (Monster (Vector2 xmon ymon) hunting (Wander WalkDown n))
  | ymon > monsterSize/2 = Monster (Vector2 xmon (ymon - monsterSpeed)) False (Wander WalkDown (n-1))
  | otherwise = Monster (Vector2 xmon ymon) False (Wander WalkUp (n-1))
wander _ (Monster (Vector2 xmon ymon) hunting (Wander WalkLeft n))
  | xmon > monsterSize/2 = Monster (Vector2 (xmon - monsterSpeed) ymon) False (Wander WalkLeft (n-1))
  | otherwise = Monster (Vector2 xmon ymon) False (Wander WalkRight (n-1)) -- about-face
wander _ (Monster (Vector2 xmon ymon) hunting (Wander WalkRight n))
  | xmon < (fromIntegral(width) - monsterSize/2) = Monster (Vector2 (xmon + monsterSpeed) ymon) False (Wander WalkRight (n-1))
  | otherwise = Monster (Vector2 xmon ymon) False (Wander WalkLeft (n-1)) -- about-face

-- number conversions
-- type GLdouble = CDouble
glDoubleToDouble :: GLdouble -> Double
glDoubleToDouble (CDouble x) = realToFrac x

renderFrame window (Player (Vector2 xpos ypos)) monster@(Monster (Vector2 xmon ymon) hunting (Wander direction _)) n = do
   print $ head n
   print monster
   clear [ColorBuffer]
   color $ Color4 0 0 0 (1 :: GLfloat)
   renderPrimitive Quads $ do
        vertex $ Vertex2 (xpos - playerSize/2) (ypos - playerSize/2)
        vertex $ Vertex2 (xpos + playerSize/2) (ypos - playerSize/2)
        vertex $ Vertex2 (xpos + playerSize/2) (ypos + playerSize/2)
        vertex $ Vertex2 (xpos - playerSize/2) (ypos + playerSize/2)
   color $ monsterColor hunting
   renderPrimitive Triangles $ do
        vertex $ Vertex2 (xmon - monsterSize/2) (ymon - monsterSize/2)
        vertex $ Vertex2 (xmon + monsterSize/2) (ymon - monsterSize/2)
        vertex $ Vertex2 xmon (ymon + monsterSize/2)
   flush
   swapBuffers window

monsterColor True = Color4 1 0 0 (1 :: GLfloat) -- red hunting
monsterColor False = Color4 0 1 0 (1 :: GLfloat) -- green wandering

withWindow :: Int -> Int -> String -> (GLFW.Window -> IO ()) -> IO ()
withWindow width height title f = do
    GLFW.setErrorCallback $ Just simpleErrorCallback
    r <- GLFW.init
    when r $ do
        m <- GLFW.createWindow width height title Nothing Nothing
        case m of
          (Just win) -> do
              GLFW.makeContextCurrent m
              f win
              GLFW.setErrorCallback $ Just simpleErrorCallback
              GLFW.destroyWindow win
          Nothing -> return ()
        GLFW.terminate
  where
    simpleErrorCallback e s =
        putStrLn $ unwords [show e, show s]

keyIsPressed :: Window -> Key -> IO Bool
keyIsPressed win key = isPress `fmap` GLFW.getKey win key

isPress :: KeyState -> Bool
isPress KeyState'Pressed   = True
isPress KeyState'Repeating = True
isPress _                  = False
