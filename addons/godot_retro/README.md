[Looking for a godot 3.x compatible version?](https://github.com/ahopness/GodotRetro/tree/3.x)

------

<div align="center">
	<p align="center"> <i> 💜 Ｇｏｄｏｔ Ｒｅｔｒｏ 💜 </i> </p>
	<p align="center"> <i> Ｏｌｄ－ｓｃｈｏｏｌ ｓｈａｄｅｒ ｐａｃｋ </i> </p>
	<img src="https://img.shields.io/badge/license-CC0%20&%20MIT-b339e3?style=flat-square" align="center"></img>
	<img src="https://img.shields.io/github/stars/Ahopness/GodotRetro?color=b339e3&style=flat-square" align="center"></img>
	<img src="https://img.shields.io/github/forks/Ahopness/GodotRetro?color=b339e3&style=flat-square" align="center"></img>
	<img src="https://img.shields.io/github/repo-size/Ahopness/GodotRetro?color=b339e3&style=flat-square" align="center"></img>
	<img src="https://img.shields.io/github/last-commit/Ahopness/GodotRetro?color=b339e3&style=flat-square" align="center"></img>
	<br> <br>
	<img src="https://user-images.githubusercontent.com/56614267/187816590-4fc9e419-84ba-4082-bfaf-e6f02001824d.png" alt="Logo" width="50%"></img>
	<hr>
</div>

## Sumary

* [About](#about)
* [License](#license)
* [Shaders](#shaders)
* [Installation](#installation)
* [Examples](#examples)
* [Features](#features)
* [Limitations](#limitations)
* [Credits](#credits)



## About

**Godot Retro** is a **compositor effects** and **shader** pack for godot, with various ports of shades from *ShaderToy*, *Unity* and The *Book Of Shaders*.



## License

* Shaders

All shaders are licensed under **CC0**, with the exeption of the *Glitch* and the *NTSC Basic* shaders, that are licensed under **MIT**. 

* Example Scenes

*Models*, *scripts*, *textures* and *sounds* are all under **CC0**.

The *shrWind* shader, used in map 4, is made by **Maujoe** and it's licensed under **MIT**.



## Shaders

- CRT Simple

- CRT Complex

- TV

- VHS

- VHS Pause

- Dithering

- Posterization Simple

- Posterization Complex

- Glitch Simple

- Glitch Complex

- Grain Simple

- Grain Complex

- Lens Distortion

- Monochrome

- Sharpness

- Color Correction

- PSX (Spatial)


### Recommendation

The shaders looks better when they are combined!

**Example :**

This scene uses the following combination : **Lens Distortion + Grain + TV**

<img width="640" height="480" alt="ScreencastFrom2026-04-1619-40-52-ezgif com-optimize" src="https://github.com/user-attachments/assets/8b78da8e-c40b-4e50-a1c7-c74ff34cbba3" />

And this scene use this combination : **Lens Distortion + Sharpness + NTSC**

<img width="640" height="480" alt="ezgif com-optimize" src="https://github.com/user-attachments/assets/026c96cb-8fd1-4659-a15d-4a5c2a7aff7a" />


- Tip 1 : **Sharpness** is a must have if using any of the *TV*, *VHS* or the *NTSC* shaders for achieving a more realistic retro effect!

- Tip 2 : **Lens Distortion** and high FOV combined can give a MTV 2000 blumbers aesthetics if used correctly!

- Tip 3 : Be careful with **Grain**! It can get really messy really easily!

- Tip 4 : All of the shaders can go beyond their default range values, just open the shader code and just the numbers inside the *hint_range()* function in the variables section.

- Tip 5 : **ALWAYS** check the headers inside the shaders you are using, there's information about *compatibility*, *credits* and *licesing* in there!



## Installation

### Compositor Effect (Forward+ & Mobile Renderers)

Simply create a Compositor inside your WorldEnvironment, when adding a new CompositorEffect, a list of all available effects will automatically apear once you import the GodotRetro plugin.

<img width="438" height="972" alt="image" src="https://github.com/user-attachments/assets/5066c175-3b15-4e90-8f9d-014e8be3b18b" />

### Shader Material (Compatibility Renderer)

**To use the shaders you got to** :

1. Copy the *GodotRetro* folder to your project (can be anywhere)


***For normal shader*** :

2. Just add the shader to a *ShaderMaterial*.


***For screen space shaders*** :

2. Create a *ColorRect* and make it a *FullRect* in the *Layout* options

3. Assign the shader of preference to a *ShaderMaterial* in the used *ColorRect*.


**Example :**

![example](https://i.imgur.com/sSti5i8.png)


**Done!** Have fun!


### DISCLAMER :

- To use 2+ shaders at the same time, you need to use a BackBufferCopy set as a Viewport for each effect.

- For UI, be sure to set it above the shaders in the node hierarchy for them to be affected for more imersion.



## Examples

5 free and easy to learn examples are available with the pack.

<div align="center">
	<img width="320" height="240" alt="ScreencastFrom2026-04-1619-41-17-ezgif com-optimize" src="https://github.com/user-attachments/assets/ad13f139-8285-41b8-a88d-2663e19f8c60" />
	<img width="320" height="240" alt="ezgif com-optimize(2)" src="https://github.com/user-attachments/assets/31f9b17e-9bfd-4031-b484-24e7f7d60c5d" />
	<img width="320" height="240" alt="ezgif com-video-to-gif-converter" src="https://github.com/user-attachments/assets/27e8663b-fc7f-4241-996b-504c774f2ea2" />
</div>

**General controls**:

|    ESC    |
|-----------|
| Quit Game |

**Map 1 controls**:

|    W   |     A     |     S     |     D      |     E     |     Q     | Shift |
|--------|-----------|-----------|------------|-----------|-----------|-------|
| Foward | Turn Left | Backwards | Turn Right | Walk Left | Walk Left |  Run  |

**Map 4 controls**:

|     A     |     D      |
|-----------|------------|
| Move Left | Move Right |



## Features

 - **22** easy to use godot shaders

 - 5 well done **example projects**



## Limitations

Unfortnetly, some shaders arent 100% perfect.

 - Some shaders may not work in the web export, please check each used shader's code header for more information!



## Credits 

Shaders ported by : **Ahopness ([@ahopness](http://twitter.com/ahopness "My Twitter Account"))**

*B&W* shader where originaly made by : **demofox (ShaderToy)**

*Color Precission* shader where originaly made by : **abelcamarena (ShaderToy)**

*Jpeg Compression* shader where originaly made by : **paniq (ShaderToy)**

*Better CC* shader where originaly made by **Wunkolo(ShaderToy)**

*Lens Distortion* shader where originaly made by **jcant0n(ShaderToy)**

*Sharpness* shader where originaly made by **Nihilistic_Furry(ShaderToy)**

*Grain* shader where originaly made by **spl!te(GitHub) & martinsh(Personal Blog)**

*Simple Grain* shader where originaly made by : **juniorxsound (ShaderToy)**

*TV* shader where originaly made by : **ehj1 (ShaderToy)**

*VHS* shader where originaly made by : **FMS_Cat (ShaderToy)**

*VHS Pause* shader where originaly made by : **caaaaaaarter (ShaderToy)**

*NTSC* shader where originaly made by : **ompuco (ShaderToy)**

*NTSC Basic* shader where originaly made by : **keijiro (Github)**

*Glitch* shader where originaly made by : **keijiro (GitHub)**

*Simple Glitch* shader where originaly made by : **Gaktan (ShaderToy)**

*Blur* shader where originaly made by : **jcant0n (ShaderToy)**

*Hello World* and *Hello World 2* shaders where originaly made by : **Patricio Gonzalez Vivo** 
