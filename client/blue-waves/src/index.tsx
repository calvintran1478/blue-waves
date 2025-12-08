import { lazy, createContext, createSignal } from "solid-js";
import { render } from "solid-js/web";
import { Router, Route } from "@solidjs/router";
import "./index.css"

const RegisterPage = lazy(() => import("./pages/RegisterPage"));
const LoginPage = lazy(() => import("./pages/LoginPage"));
const HomePage = lazy(() => import("./pages/HomePage"));
const LibraryPage = lazy(() => import("./pages/LibraryPage"));
const MusicPage = lazy(() => import("./pages/MusicPage"));
const PlaylistsPage = lazy(() => import("./pages/PlaylistsPage"));
const PlaylistPage = lazy(() => import("./pages/PlaylistPage"));

export const apiDomain = import.meta.env.PROD ? "https://server-green-violet-721.fly.dev" : "http://localhost:8080";
export const AuthContext = createContext();

function AuthProvider(props: any) {
    const [token, setToken] = createSignal("")

    return (
        <AuthContext.Provider value={[token, setToken]}>
            {props.children}
        </AuthContext.Provider>
    )
}

render(
    () => (
        <Router root={(props) => <AuthProvider>{props.children}</AuthProvider>}>
            <Route path="/register" component={RegisterPage}/>
            <Route path="/login" component={LoginPage}/>
            <Route path="/home" component={HomePage}/>
            <Route path="/library" component={LibraryPage}/>
            <Route path="/library/:music_id" component={MusicPage}/>
            <Route path="/playlists" component={PlaylistsPage}/>
            <Route path="/playlists/:playlist_id" component={PlaylistPage}/>
        </Router>  
    ),
    document.getElementById("root")!
);
