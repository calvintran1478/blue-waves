import { lazy } from 'solid-js';
import { render } from 'solid-js/web'
import { Router } from "@solidjs/router"
import "./index.css"

const RegisterPage = lazy(() => import("./pages/RegisterPage"));
const LoginPage = lazy(() => import("./pages/LoginPage"));

const routes = [
    {
        path: "/register",
        component: RegisterPage,
    },
    {
        path: "/login",
        component: LoginPage
    }
]

render(() => <Router>{routes}</Router>, document.getElementById("root")!)
