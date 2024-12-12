import { A } from "@solidjs/router";

const HomePage = () => {

    return (
        <div class="flex">
            <div class="flex flex-col w-1/5 h-screen border-2">
                <nav class="flex flex-col items-center p-6">
                    <A href="/library" class="text-2xl font-medium m-6">Library</A>
                    <A href="/playlists" class="text-2xl font-medium m-6">Playlists</A>
                </nav>
            </div>
            <div class="flex flex-col w-4/5">
                <div class="flex justify-between h-20 p-6">
                    <h1 class="text-2xl font-medium">Recently Played</h1>
                    <A href="/recently-played" class="text-2xl ">See All</A>
                </div>
            </div>
        </div>
    )
}

export default HomePage;
