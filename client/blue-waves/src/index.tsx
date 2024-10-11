import { lazy } from 'solid-js';
import { render } from 'solid-js/web'
import { Router } from "@solidjs/router"

const RegisterPage = lazy(() => import("./pages/RegisterPage"));

const routes = [
    {
        path: "/register",
        component: RegisterPage,
    }
]

render(() => <Router>{routes}</Router>, document.getElementById("root")!)
