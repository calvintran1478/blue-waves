import { lazy } from 'solid-js';
import { render } from 'solid-js/web'
import { Router } from "@solidjs/router"
import { QueryClient, QueryClientProvider } from '@tanstack/solid-query'; 
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

const queryClient = new QueryClient();

render(
    () => (
        <QueryClientProvider client={queryClient}>
            <Router>{routes}</Router>
        </QueryClientProvider>
    ),
    document.getElementById("root")!
);
