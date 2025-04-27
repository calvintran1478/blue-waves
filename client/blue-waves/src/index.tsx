import { lazy } from "solid-js";
import { render } from "solid-js/web";
import { Router } from "@solidjs/router";
import "./index.css"

const RegisterPage = lazy(() => import("./pages/RegisterPage"));
const LoginPage = lazy(() => import("./pages/LoginPage"));
const HomePage = lazy(() => import("./pages/HomePage"));
const LibraryPage = lazy(() => import("./pages/LibraryPage"));
const MusicPage = lazy(() => import("./pages/MusicPage"));

const routes = [
    {
        path: "/register",
        component: RegisterPage,
    },
    {
        path: "/login",
        component: LoginPage
    },
    {
        path: "/home",
        component: HomePage
    },
    {
        path: "/library",
        component: LibraryPage
    },
    {
        path: "/library/:music_id",
        component: MusicPage
    }
]

render(() => <Router>{routes}</Router>, document.getElementById("root")!);
